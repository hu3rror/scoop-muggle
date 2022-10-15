# Scoop Muggle Bucket [![Build status](https://ci.appveyor.com/api/projects/status/eiyp2qhs11n83jo0/branch/main?svg=true)](https://ci.appveyor.com/project/hu3rror/scoop-muggle/branch/master)

## Add this Bucket / 添加本 Bucket 仓库

``` pwsh
scoop bucket add muggle 'https://github.com/hu3rror/scoop-muggle.git'
```

## Software list / 软件清单

Find the software lis in this bucket: [Click here](bucket) / 本 Bucket 包含的软件清单: [点击查看](bucket)

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
