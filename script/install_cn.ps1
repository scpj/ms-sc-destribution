param (
    $token,
    $key
)
# Download latest release from github
if($PSVersionTable.PSVersion.Major -lt 5){
    Write-Host "Require PS >= 5,your PSVersion:"$PSVersionTable.PSVersion.Major -BackgroundColor DarkGreen -ForegroundColor White
    exit
}
$clientrepo = "scpj/ms-sc-destribution"
$nssmrepo = "nezhahq/nssm-backup"
#  x86 or x64
if ([System.Environment]::Is64BitOperatingSystem) {
    $file = "miaospeed-sc-windows-amd64.exe"
}
else {
    Write-Host "Your system is 32-bit, please use 64-bit operating system" -BackgroundColor DarkGreen -ForegroundColor White
    exit
}
$clientreleases = "https://pserv.wmxwork.top/api/ga?op=r&r=$clientrepo"
$nssmreleases = "https://pserv.wmxwork.top/api/ga?op=r&r=$nssmrepo"
#重复运行自动更新
if (Test-Path "C:\miaospeed") {
    Write-Host "miaospeed already exists, delete and reinstall" -BackgroundColor DarkGreen -ForegroundColor White
    C:/miaospeed/nssm.exe stop miaospeed
    C:/miaospeed/nssm.exe remove miaospeed
    Remove-Item "C:\miaospeed" -Recurse
}

#TLS/SSL
Write-Host "Determining latest miaospeed release" -BackgroundColor DarkGreen -ForegroundColor White
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$agenttag = (Invoke-WebRequest -Uri $clientreleases -UseBasicParsing | ConvertFrom-Json)[0].tag_name
$nssmtag = (Invoke-WebRequest -Uri $nssmreleases -UseBasicParsing | ConvertFrom-Json)[0].tag_name
$download = "https://ghp.ci/https://github.com/$clientrepo/releases/download/$agenttag/$file"
$nssmdownload="https://ghp.ci/https://github.com/$nssmrepo/releases/download/$nssmtag/nssm.zip"
Write-Host "Location:CN,use mirror address" -BackgroundColor DarkRed -ForegroundColor Green
echo $download
echo $nssmdownload
Invoke-WebRequest $nssmdownload -OutFile "C:\nssm.zip"
Invoke-WebRequest $download -OutFile "C:\miaospeed.exe"
#使用nssm安装服务

#解压
Expand-Archive "C:\nssm.zip" -DestinationPath "C:\temp" -Force
if (!(Test-Path "C:\miaospeed")) { New-Item -Path "C:\miaospeed" -type directory }

#整理文件
Move-Item -Path "C:\miaospeed.exe" -Destination "C:\miaospeed\miaospeed.exe"
Move-Item -Path "C:\temp\nssm-2.24\win64\nssm.exe" -Destination "C:\miaospeed\nssm.exe"

#清理垃圾
Remove-Item "C:\nssm.zip"
Remove-Item "C:\temp" -Recurse
#安装部分
C:\miaospeed\nssm.exe install miaospeed C:\miaospeed\miaospeed.exe server --token $token --frpkey $key
C:\miaospeed\nssm.exe start miaospeed
#enjoy
Write-Host "Enjoy It!" -BackgroundColor DarkGreen -ForegroundColor Red
