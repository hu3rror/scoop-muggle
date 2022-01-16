# Scoop Muggle Bucket [![Build status](https://ci.appveyor.com/api/projects/status/eiyp2qhs11n83jo0/branch/main?svg=true)](https://ci.appveyor.com/project/hu3rror/scoop-muggle/branch/master)

## Add this Bucket / 添加本 Bucket 仓库

``` pwsh
scoop bucket add muggle 'https://github.com/hu3rror/scoop-muggle.git'
```

## Software list / 软件清单

Find the software lis in this bucket: [Click here](bucket)

本 Bucket 包含的软件清单: [点击查看](bucket)

---

## What & How to

### What is `Scoop`?
Please visit the [official website](https://scoop.sh/) and it included the installation tutorial.

### [Example] How to install `Logseq` or `Logseq Nightly`?
1. Once Scoop is installed, executing the following command in Powershell and it would add this Scoop Bucket into your system:

    ``` pwsh
    scoop bucket add muggle 'https://github.com/hu3rror/scoop-muggle.git'
    ```

2. Then try to install `Logseq`:

    ``` pwsh
    scoop install muggle/logseq
    ```
    or install `Logseq nightly` version:

    ``` pwsh
    scoop install muggle/logseq-nightly
    ```

### [Example] How to update `Logseq`?
1. Execute the following command in `Powershell`:

    ``` pwsh
    scoop update logseq
    ```

2. or update all programs by:

    ``` pwsh
    scoop update *
    ```

🎉🎉 Everything set.

---

## 中文教程

### 添加本 `Bucket` 仓库
``` pwsh
scoop bucket add muggle 'https://github.com/hu3rror/scoop-muggle.git'
```

#### `Scoop` 是什么？
参考 [SpencerWoo](https://sspai.com/u/spencerwoo/updates) 撰写的 [「一行代码」搞定软件安装卸载，用 Scoop 管理你的 Windows 软件](https://sspai.com/post/52496)

#### `Scoop` 简明安装教程
> 内容摘抄自上述 scoop [文章介绍](https://sspai.com/post/52496)，更多详情请参考 [Scoop 官网](https://scoop.sh/)

1. 右键开始菜单按钮，在右键菜单中打开 `PowerShell`;
2. 在 `PowerShell` 中输入下面内容，保证允许本地脚本的执行：

    ``` pwsh
    set-executionpolicy remotesigned -scope currentuser
    ```

3. 然后执行下面的命令安装 `Scoop`：

    ``` pwsh
    iex (new-object net.webclient).downloadstring('https://get.scoop.sh')
    ```

#### [参考例子] 使用 `Scoop` 安装 `Logseq` 教程
1. 在 Powershell 中继续执行以下命令以添加本 `Bucket` 仓库:

    ``` pwsh
    scoop bucket add muggle 'https://github.com/hu3rror/scoop-muggle.git'
    ```

2. 继续执行以下命令安装 `Logseq`

    ``` pwsh
    scoop install muggle/logseq
    ```
3. 或安装正快速修复 Bugs 的 `Logseq Nightly` 版本

    ``` pwsh
    scoop install muggle/logseq-nightly
    ```

3. 等待下载完毕即自动完成安装即可，之后可在开始菜单中找到 `Logseq` 的启动快捷方式。

#### [参考例子] 使用 `Scoop` 更新 `Logseq`
1. 若仅更新 `Logseq` ，可以在 `Powershell` 中执行以下命令：

    ``` pwsh
    scoop update logseq
    ```

2. 若希望其他 `Scoop` 库的软件都一并更新，则可以在 `Powershell` 中执行以下命令：

    ```  pwsh
    scoop update *
    ```

#### 注意事项
1. `Powershell` 建议在管理员权限身份下运行，可通过安装 `sudo` 包来快速实现:

    ``` pwsh
    scoop install sudo
    ```

    后续若需要快速提权，只需在命令最前面添加 `sudo`:

    ``` pwsh
    sudo scoop install aria2 -g
    ```

2. 关于下载速度慢的原因，有两种方式解决
    1. 在 `Scoop` 中安装 `aria2`，实现多线程下载安装包：

        ``` pwsh
        scoop install aria2
        ```

        或全局安装

        ``` pwsh
        sudo scoop install aria2 -g
        ```

    2. 让 Windows 终端（Powershell/CMD）走系统代理，也许可以参考：[在 Windows 终端中设置代理](https://www.yixuju.cn/other/talking-about-proxy/)

🎉🎉 大功告成！
