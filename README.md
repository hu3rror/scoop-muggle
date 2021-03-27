# Scoop Muggle Bucket [![Build status](https://ci.appveyor.com/api/projects/status/eiyp2qhs11n83jo0/branch/master?svg=true)](https://ci.appveyor.com/project/Hue/scoop-muggle/branch/master)

## Add bucket

`scoop bucket add muggle 'https://github.com/HueLiu/scoop-muggle.git'`

## For reference only

https://cn.logseq.com/t/topic/491

### scoop 是什么？
参考 [SpencerWoo](https://sspai.com/u/spencerwoo/updates) 撰写的 [「一行代码」搞定软件安装卸载，用 Scoop 管理你的 Windows 软件](https://sspai.com/post/52496)

### scoop 简明安装教程
> 内容摘抄自上述 scoop 介绍[文章](https://sspai.com/post/52496)，更多详情请参考 [scoop 官网](https://scoop.sh/)

1. 右键开始菜单按钮，在右键菜单中打开 PowerShell
2. 在 PowerShell 中输入下面内容，保证允许本地脚本的执行：
    `set-executionpolicy remotesigned -scope currentuser`

3. 然后执行下面的命令安装 Scoop：
    `iex (new-object net.webclient).downloadstring('https://get.scoop.sh')`

### 使用 scoop 安装 Logseq Desktop 教程
1. 在 Powershell 中继续执行以下命令
    `scoop bucket add muggle 'https://github.com/HueLiu/scoop-muggle.git'`

2. 上述代码是添加 scoop bucket 库，然后继续执行以下命令安装 Logseq Desktop
    `scoop install muggle/logseq`

3. 等待下载完毕即自动完成安装，默认会在系统开始菜单添加 Logseq 的快捷方式。

### 使用 scoop 更新 Logseq Desktop
1. 若仅更新 Logseq Desktop 版本，可以在 Powershell 中执行以下命令：
    `scoop update logseq`

2. 若希望其他 scoop 库的软件都一并更新，则可以在 Powershell 中执行以下命令：
    `scoop update *`

### 注意事项
1. 仅支持 Windows 版本的 Logseq Desktop 更新
2. Powershell 建议在管理员权限身份下运行，避免一些额外的权限问题（当然上述 Logseq 的安装不需要管理员权限）
3. 该教程至 Logseq 0.0.13 版本可用。后续 Logseq 如果更换安装模式，上述方式可能不适用。
4. 由于个人也是 scoop 新手，所以后续的维护会尽量而为。
5. 关于下载速度慢的原因，有两种方式解决
    1. 在 Logseq 中安装 aria2，实现多线程下载安装包： `scoop install aria2`
    2. 让 Windows 终端（Powershell/CMD）走系统代理，也许可以参考：[在 Windows 终端中设置代理](https://www.yixuju.cn/other/talking-about-proxy/)

🎉🎉 Everything set.
