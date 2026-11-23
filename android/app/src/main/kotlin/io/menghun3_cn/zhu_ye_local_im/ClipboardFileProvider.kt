package io.menghun3_cn.zhu_ye_local_im

import androidx.core.content.FileProvider

/**
 * The FileProvider the pasteboard plugin's clipboard URIs resolve through.
 *
 * It is a distinct class on purpose: Android runs one provider instance per
 * class name within a package, so declaring the clipboard provider as the same
 * `androidx.core.content.FileProvider` the update installer uses makes the two
 * authorities collide — requests for `${applicationId}.provider` are served by
 * the update provider's instance, which does not know the clipboard paths, and
 * every image copy lands on the clipboard without a readable type. A subclass
 * gives the clipboard authority its own instance without changing what either
 * provider exposes.
 */
class ClipboardFileProvider : FileProvider()
