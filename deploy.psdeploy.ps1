Deploy "Deploy ServerBackup To Dev Folder" {
    By FileSystem {
        FromSource ServerBackup
        To "C:\PSDev\ServerBackup"
        WithOptions @{
            Mirror = $True
        }
        Tagged Dev
    }
}

Deploy "Deplot ServerBackup To Production Folder" {
    By FileSystem {
        FromSource ServerBackup
        To "\\robocop\ScriptRepo\ServerBackup"
        WithOptions @{
            Mirror = $True
        }
        Tagged Prod
    }
}