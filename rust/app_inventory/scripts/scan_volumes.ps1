$volumes = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
  Select-Object DeviceID,FileSystem,Size,FreeSpace
[pscustomobject]@{
  volumes = @($volumes | ForEach-Object {
    [pscustomobject]@{
      drive = [string]$_.DeviceID
      fileSystem = [string]$_.FileSystem
      totalBytes = [int64]$_.Size
      freeBytes = [int64]$_.FreeSpace
    }
  })
} | ConvertTo-Json -Depth 4 -Compress
