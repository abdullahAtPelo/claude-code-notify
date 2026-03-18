package com.claudecode.terminal

import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.application.ApplicationNamesInfo
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import com.intellij.openapi.project.ProjectManager
import com.intellij.openapi.wm.ToolWindowManager
import com.intellij.ui.content.Content
import com.intellij.ui.content.ContentManagerEvent
import com.intellij.ui.content.ContentManagerListener
import com.intellij.terminal.JBTerminalWidget
import com.jediterm.terminal.TtyConnector
import io.netty.buffer.Unpooled
import io.netty.channel.ChannelHandlerContext
import io.netty.handler.codec.http.*
import org.jetbrains.ide.HttpRequestHandler

class TerminalFocusHandler : HttpRequestHandler() {
    companion object {
        private val LOG = Logger.getInstance(TerminalFocusHandler::class.java)
        @Volatile
        private var cachedBundleId: String? = null
    }

    override fun isSupported(request: FullHttpRequest): Boolean {
        return request.uri().startsWith("/api/claude/terminal")
    }

    override fun process(
        urlDecoder: QueryStringDecoder,
        request: FullHttpRequest,
        context: ChannelHandlerContext
    ): Boolean {
        when (urlDecoder.path()) {
            "/api/claude/terminal/health" -> handleHealth(context)
            "/api/claude/terminal/tabs" -> handleListTabs(context)
            "/api/claude/terminal/focus" -> handleFocus(urlDecoder, context)
            else -> return false
        }
        return true
    }

    private fun handleHealth(context: ChannelHandlerContext) {
        sendJson(context, HttpResponseStatus.OK, """{"status":"ok"}""")
    }

    private fun handleListTabs(context: ChannelHandlerContext) {
        val tabs = mutableListOf<String>()
        try {
            ApplicationManager.getApplication().invokeAndWait {
                for (project in ProjectManager.getInstance().openProjects) {
                    val toolWindow = ToolWindowManager.getInstance(project)
                        .getToolWindow("Terminal") ?: continue
                    val cm = toolWindow.contentManager
                    val viewMap = buildContentViewMap(project)
                    for (content in cm.contents) {
                        val selected = cm.selectedContent == content
                        val pid = getShellPid(content, viewMap)
                        val pidJson = if (pid > 0) ""","pid":$pid""" else ""
                        tabs.add(
                            """{"project":"${esc(project.name)}","tab":"${esc(content.displayName ?: "")}","selected":$selected$pidJson}"""
                        )
                    }
                }
            }
        } catch (_: Exception) {}
        sendJson(context, HttpResponseStatus.OK, "[${tabs.joinToString(",")}]")
    }

    private fun getShellPid(content: Content, viewMap: Map<Content, Any>): Long {
        // Classic terminal (PyCharm, older IDEs): JBTerminalWidget in Swing tree
        try {
            val widget = findTerminalWidget(content.component)
            if (widget != null) {
                val connector = widget.processTtyConnector ?: return -1
                return connector.process.pid()
            }
        } catch (_: Exception) {}

        // New terminal (IntelliJ 2025.x+): resolve via TerminalView session
        val view = viewMap[content] ?: return -1
        return getNewTerminalPid(view)
    }

    /**
     * Build Content → TerminalView map via TerminalToolWindowTabsManager (2025.x+).
     * Uses reflection since this API doesn't exist in older IDEs.
     */
    private fun buildContentViewMap(project: Project): Map<Content, Any> {
        return try {
            val mgrClass = Class.forName(
                "com.intellij.terminal.frontend.toolwindow.TerminalToolWindowTabsManager"
            )
            // getInstance is @JvmStatic on the Companion → callable as static method
            val manager = mgrClass.getMethod("getInstance", Project::class.java)
                .invoke(null, project) ?: return emptyMap()
            val tabs = manager.javaClass.getMethod("getTabs").invoke(manager) as? List<*>
                ?: return emptyMap()
            val tabClass = Class.forName(
                "com.intellij.terminal.frontend.toolwindow.TerminalToolWindowTab"
            )
            val getContent = tabClass.getMethod("getContent")
            val getView = tabClass.getMethod("getView")
            val map = mutableMapOf<Content, Any>()
            for (tab in tabs) {
                tab ?: continue
                val content = getContent.invoke(tab) as? Content ?: continue
                val view = getView.invoke(tab) ?: continue
                map[content] = view
            }
            map
        } catch (_: Exception) {
            emptyMap()
        }
    }

    /**
     * Extract shell PID from a new terminal TerminalView via reflection.
     * Path: TerminalViewImpl.sessionFuture → FrontendTerminalSession.id
     *     → TerminalSessionsManager.getSession(id) → backend chain → ttyConnector → pid
     */
    private fun getNewTerminalPid(view: Any): Long {
        try {
            val sessionField = view.javaClass.getDeclaredField("sessionFuture")
            sessionField.isAccessible = true
            val future = sessionField.get(view) as? java.util.concurrent.CompletableFuture<*>
                ?: return -1
            if (!future.isDone) return -1
            val frontendSession = future.get() ?: return -1

            // Get the session ID from FrontendTerminalSession
            val idField = frontendSession.javaClass.getDeclaredField("id")
            idField.isAccessible = true
            val sessionId = idField.get(frontendSession) ?: return -1

            // Look up the backend session via TerminalSessionsManager
            val mgrClass = Class.forName("com.intellij.terminal.backend.TerminalSessionsManager")
            val mgr = mgrClass.getMethod("getInstance").invoke(null) ?: return -1
            val backendSession = mgrClass.getMethod("getSession", sessionId.javaClass).invoke(mgr, sessionId)
                ?: return -1

            // Walk the delegation chain to find ttyConnector
            val connector = findTtyConnector(backendSession) ?: return -1

            val ptc = org.jetbrains.plugins.terminal.ShellTerminalWidget
                .getProcessTtyConnector(connector) ?: return -1
            return ptc.process.pid()
        } catch (_: Exception) {}
        return -1
    }

    /** Walk delegate chain (StateAwareTerminalSession → BackendTerminalSessionImpl) to find ttyConnector. */
    private fun findTtyConnector(session: Any): TtyConnector? {
        // Try ttyConnector field directly (BackendTerminalSessionImpl)
        try {
            val f = session.javaClass.getDeclaredField("ttyConnector")
            f.isAccessible = true
            return f.get(session) as? TtyConnector
        } catch (_: NoSuchFieldException) {}

        // Try delegate field (StateAwareTerminalSession wraps BackendTerminalSessionImpl)
        try {
            val f = session.javaClass.getDeclaredField("delegate")
            f.isAccessible = true
            val delegate = f.get(session) ?: return null
            return findTtyConnector(delegate)
        } catch (_: NoSuchFieldException) {}

        return null
    }

    private fun findTerminalWidget(component: java.awt.Component): JBTerminalWidget? {
        if (component is JBTerminalWidget) return component
        if (component is java.awt.Container) {
            for (child in component.components) {
                findTerminalWidget(child)?.let { return it }
            }
        }
        return null
    }

    private fun getBundleId(): String {
        cachedBundleId?.let { return it }

        val result = resolveBundleId()
        if (result.isNotEmpty()) cachedBundleId = result
        return result
    }

    private fun resolveBundleId(): String {
        val sysProp = System.getProperty("__CFBundleIdentifier")
        if (!sysProp.isNullOrEmpty()) return sysProp

        // Try product name mapping first (instant, covers all common JetBrains IDEs)
        val product = ApplicationNamesInfo.getInstance().productName.lowercase()
        val mapped = when {
            "goland" in product -> "com.jetbrains.goland"
            "intellij" in product -> "com.jetbrains.intellij"
            "pycharm" in product -> "com.jetbrains.pycharm"
            "webstorm" in product -> "com.jetbrains.webstorm"
            "rider" in product -> "com.jetbrains.rider"
            "phpstorm" in product -> "com.jetbrains.phpstorm"
            "clion" in product -> "com.jetbrains.clion"
            "rubymine" in product -> "com.jetbrains.rubymine"
            "datagrip" in product -> "com.jetbrains.datagrip"
            else -> null
        }
        if (mapped != null) return mapped

        // Fallback: ask System Events (slow, only for unknown IDEs)
        try {
            val proc = ProcessBuilder("osascript", "-e",
                "tell application \"System Events\" to get bundle identifier of (first application process whose unix id is ${ProcessHandle.current().pid()})"
            ).start()
            val result = proc.inputStream.bufferedReader().readText().trim()
            proc.waitFor()
            if (result.isNotEmpty()) return result
        } catch (_: Exception) {}

        return ""
    }

    private fun handleFocus(urlDecoder: QueryStringDecoder, context: ChannelHandlerContext) {
        val targetProject = urlDecoder.parameters()["project"]?.firstOrNull()
        val targetTab = urlDecoder.parameters()["tab"]?.firstOrNull()

        sendJson(context, HttpResponseStatus.OK, """{"focused":true}""")

        ApplicationManager.getApplication().executeOnPooledThread {
            try {
                var project: Project? = null
                ApplicationManager.getApplication().invokeAndWait {
                    project = ProjectManager.getInstance().openProjects.firstOrNull {
                        targetProject == null || it.name == targetProject
                    }
                }
                val proj = project ?: return@executeOnPooledThread

                val bundleId = getBundleId()
                if (bundleId.isNotEmpty()) {
                    ProcessBuilder(
                        "osascript",
                        "-e", "tell application id \"$bundleId\" to activate",
                        "-e", "tell application \"System Events\"",
                        "-e", "  tell (first application process whose bundle identifier is \"$bundleId\")",
                        "-e", "    try",
                        "-e", "      set targetWindow to first window whose name contains \"${esc(proj.name)}\"",
                        "-e", "      perform action \"AXRaise\" of targetWindow",
                        "-e", "    end try",
                        "-e", "  end tell",
                        "-e", "end tell"
                    ).start().waitFor()
                }

                if (targetTab != null) {
                    ApplicationManager.getApplication().invokeLater {
                        val toolWindow = ToolWindowManager.getInstance(proj)
                            .getToolWindow("Terminal") ?: return@invokeLater

                        // Activate the Terminal panel first, then switch tabs in the callback
                        toolWindow.activate {
                            val cm = toolWindow.contentManager
                            val content = cm.contents.firstOrNull { it.displayName == targetTab }
                                ?: return@activate

                            cm.setSelectedContent(content, true)

                            // Listen for selection changes to counter GoLand's state restoration
                            val listener = object : ContentManagerListener {
                                private var corrections = 0
                                override fun selectionChanged(event: ContentManagerEvent) {
                                    if (event.content != content && corrections < 5) {
                                        corrections++
                                        cm.setSelectedContent(content, true)
                                    } else {
                                        cm.removeContentManagerListener(this)
                                    }
                                }
                            }
                            cm.addContentManagerListener(listener)
                        }
                    }
                }
            } catch (e: Exception) {
                LOG.warn("FOCUS: exception", e)
            }
        }
    }

    private fun sendJson(context: ChannelHandlerContext, status: HttpResponseStatus, json: String) {
        val bytes = json.toByteArray(Charsets.UTF_8)
        val response = DefaultFullHttpResponse(
            HttpVersion.HTTP_1_1,
            status,
            Unpooled.wrappedBuffer(bytes)
        )
        response.headers().apply {
            set(HttpHeaderNames.CONTENT_TYPE, "application/json; charset=utf-8")
            set(HttpHeaderNames.CONTENT_LENGTH, bytes.size)
        }
        context.writeAndFlush(response)
    }

    private fun esc(s: String) = s.replace("\\", "\\\\").replace("\"", "\\\"")
}
