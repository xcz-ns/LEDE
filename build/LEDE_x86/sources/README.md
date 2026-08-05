## OpenWrt 源码文件替换指南（编译生效）

**注意：本方法适用于在 OpenWrt 源码目录中替换文件，用于重新编译固件。**

在基于源码编译 OpenWrt 时，可以通过以下两种方式替换系统默认文件（如 banner、网络默认配置等）。

### 方法一：手动添加单个文件（按路径替换）

1. 在网页界面点击 **Add file** -> **Create new file**。

2. 在路径栏中填入源码中的相对路径，例如：

   Plaintext

   ```
   package/base-files/files/etc/banner
   ```

3. 在文本框内粘贴新的文件内容。

4. 点击 **Save** 保存。

### 方法二：批量上传文件夹（保持目录结构）

1. 在本地电脑按源码路径建好目录结构，例如：

   Plaintext

   ```
   package/
   └── base-files/
       └── files/
           └── etc/
               └── banner
   ```

   *提示：建文件时可先新建 `banner.txt`，编辑完成后删除 `.txt` 后缀。*

2. 点击 **Create new file** -> **Upload files**。

3. 将本地的 `package` 文件夹直接拖入上传框。

4. 传输完成后点击 **Save**。

### 注意事项

- 替换路径必须严格匹配 OpenWrt 源码的相对路径，否则编译时不会生效。
- 文件修改完成后，需重新执行编译流程（如 `make -j$(nproc)`）生成新固件。
