package com.claudecode.terminal

import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.application.ApplicationNamesInfo
import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.project.Project
import com.intellij.openapi.project.ProjectManager
import com.intellij.openapi.wm.ToolWindowManager
import com.intellij.ui.content.ContentManagerEvent
import com.intellij.ui.content.ContentManagerListener
import io.netty.buffer.Unpooled
import io.netty.channel.ChannelHandlerContext
import io.netty.handler.codec.http.*
import org.jetbrains.ide.HttpRequestHandler

class TerminalFocusHandler : HttpRequestHandler() {
    companion object {
        private val LOG = Logger.getInstance(TerminalFocusHandler::class.java)
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
                    for (content in cm.contents) {
                        val selected = cm.selectedContent == content
                        tabs.add(
                            """{"project":"${esc(project.name)}","tab":"${esc(content.displayName ?: "")}","selected":$selected}"""
                        )
                    }
                }
            }
        } catch (_: Exception) {}
        sendJson(context, HttpResponseStatus.OK, "[${tabs.joinToString(",")}]")
    }

    private fun getBundleId(): String {
        val sysProp = System.getProperty("__CFBundleIdentifier")
        if (!sysProp.isNullOrEmpty()) return sysProp

        try {
            val proc = ProcessBuilder("osascript", "-e",
                "tell application \"System Events\" to get bundle identifier of (first application process whose unix id is ${ProcessHandle.current().pid()})"
            ).start()
            val result = proc.inputStream.bufferedReader().readText().trim()
            proc.waitFor()
            if (result.isNotEmpty()) return result
        } catch (_: Exception) {}

        val product = ApplicationNamesInfo.getInstance().productName.lowercase()
        return when {
            "goland" in product -> "com.jetbrains.goland"
            "intellij" in product -> "com.jetbrains.intellij"
            "pycharm" in product -> "com.jetbrains.pycharm"
            "webstorm" in product -> "com.jetbrains.webstorm"
            "rider" in product -> "com.jetbrains.rider"
            "phpstorm" in product -> "com.jetbrains.phpstorm"
            "clion" in product -> "com.jetbrains.clion"
            "rubymine" in product -> "com.jetbrains.rubymine"
            "datagrip" in product -> "com.jetbrains.datagrip"
            else -> ""
        }
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
                        val cm = toolWindow.contentManager
                        val content = cm.contents.firstOrNull { it.displayName == targetTab }
                            ?: return@invokeLater

                        // Switch immediately
                        cm.setSelectedContent(content, true)

                        // Listen for selection changes to counter GoLand's state restoration
                        val listener = object : ContentManagerListener {
                            private var corrections = 0
                            override fun selectionChanged(event: ContentManagerEvent) {
                                if (event.content != content && corrections < 5) {
                                    corrections++
                                    cm.setSelectedContent(content, true)
                                }
                            }
                        }
                        cm.addContentManagerListener(listener)

                        // Clean up listener after window activation settles
                        ApplicationManager.getApplication().executeOnPooledThread {
                            Thread.sleep(2000)
                            ApplicationManager.getApplication().invokeLater {
                                cm.removeContentManagerListener(listener)
                            }
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
