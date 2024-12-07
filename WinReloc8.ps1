<#
WinReloc8
   A PowerShell script by Ben Kennish (ben@kennish.net)

Allows easily relocating a folder from one place to another (e.g. on a 
different hard disk), creating a redirecting 'junction' which means that any 
app that is set up to find the folder in the original location will still work 
fine.

Technical info: the existing location of the folder must be on an NTFS 
formatted partition

TODO: have a "Simple" mode (and default to it?) where it will have a standard folder location, such as X:\Reloc8d and the user selects a folder, and then a drive (excluding the drive hosting the original folder) to move to.  Will user have permission to create X:\Reloc8d\ by default?

TODO: more research into how Windows reports disk usage for junctions, how user can see junctions in Explorer, whether certain apps will detect the game installed multiple times, etc

#>
[CmdletBinding()]
param (
    [string]$src,
    [string]$dst,

    [switch]$ChooseDestPath,
    [switch]$Force
)

# everyone loves UTF-8, right?
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest   # stricter rules = cleaner code  :)

# default behavior for non-terminating errors (i.e., errors that don’t normally 
# stop execution, like warnings)
# global preference variable that affects all cmdlets and functions that you 
# run after this line is executed.
$ErrorActionPreference = "Stop"

# modifies the default value of the -ErrorAction parameter for every cmdlet that has the -ErrorAction parameter
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

# used for the GUI stuff
# TODO: load only when required?
Add-Type -AssemblyName System.Windows.Forms

# in 'simple' mode, just prompt to move to a drive and then move to "X:\$standardPath"
# then can we hide this path from things that scan for games
#
# if you don't specify both a src and a dst, dst drive will be prompted and then this path added on
# no slash at the front or end please
$defaultDstPath = "Reloc8d"
#$defaultDstPath = "Program Files\Reloc8d"

# so "Reloc8d" would move C:\Games\Fortnite to X:\Reloc8d\Fortnite where X is the dst drive selected

#Set-ItemProperty -Path "X:\Reloc8d" -Name Attributes -Value ('Hidden','System')
# 'System' means that Windows Explorer won't show unless "Show protected OS files" is checked


# Display a folder selection dialog
# TODO: support the other kind of dialog (like VS Code does it when you select "Open Folder...")
function Select-Folder
{
    param ([string]$Description = "Select a folder")

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
    {
        return $dialog.SelectedPath
    }
    else
    {
        return $null
    }
}


function Select-NTFSDrive
{
    param 
    (
        # device id of a drive to exclude from the list (e.g. "C:")
        [string]$Exclude = $null
    )
    # TODO: show non-NTFS drives but greyed out and unselectable

    Write-Verbose "Select-NTFSDrive excluding $Exclude"

    # Create the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Select a destination Local NTFS Drive'
    $form.Size = New-Object System.Drawing.Size(300, 150)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog  # Prevent resizing
    $form.MaximizeBox = $false  # Disable the maximize button
    $form.MinimizeBox = $false  # Disable the minimize button
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

    # Create the ComboBox
    $comboBox = New-Object System.Windows.Forms.ComboBox
    $comboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $comboBox.Location = New-Object System.Drawing.Point(50, 40)
    $comboBox.Size = New-Object System.Drawing.Size(200, 20)

    # Get all local NTFS drives and filter them
    # .DriveType = 1  no root dir (e.g. network drive)
    # .DriveType = 2  removable disk (e.g USB flash, external disk)
    # .DriveType = 3  local disk (internal hard disk)
    # .DriveType = 4  network drive
    # .DriveType = 5  CD-ROM
    # .DriveType = 6  RAM disk
    $drives = Get-WmiObject Win32_LogicalDisk ` | Where-Object {
        $Exclude -ne $_.DeviceID `
            -and $_.DriveType -in 2, 3 `
            -and $_.FileSystem -eq "NTFS" `
            -and -not ($_.VolumeName -in "RECOVERY", "OEM")
    }

    # Set the ComboBox display member (the property that will be displayed for each item)
    $comboBox.DisplayMember = 'DisplayName'
    
    # Populate ComboBox with drive letters and labels
    foreach ($drive in $drives)
    {
        $displayText = "$($drive.VolumeName) ($($drive.DeviceID)) - $(ConvertTo-HumanReadable -Bytes $drive.FreeSpace -DecimalDigits 1) free / $(ConvertTo-HumanReadable -Bytes $drive.Size -DecimalDigits 1) total  "
        
        # this command is somehow adding to the returned data!
        $null = $comboBox.Items.Add([PSCustomObject]@{
                DriveLetter = $drive.DeviceID
                #VolumeName  = $drive.VolumeName
                DisplayName = $displayText
            })
    }
    
    # If no NTFS drives are found, display an error message and return
    if ($comboBox.Items.Count -eq 0)
    {
        $null = [System.Windows.Forms.MessageBox]::Show("No NTFS drives found.")
        return $null
    } 

    # Create the OK button
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = 'OK'
    $okButton.Location = New-Object System.Drawing.Point(100, 70)

    $okButton.Add_Click(
        {
            $selectedItem = $comboBox.SelectedItem
            if ($null -ne $selectedItem)
            {
                # Access the DriveLetter property correctly
                $form.Tag = $selectedItem.DriveLetter
            }
            $form.Close()
        }
    )

    # Add controls to the form
    $form.Controls.Add($comboBox)
    $form.Controls.Add($okButton)
   
    # Show the form and wait for user input
    $null = $form.ShowDialog()

    # Return the selected drive letter if any, otherwise $null
    return ($form.Tag)
}



# Convert a number of bytes into a more human readable string format
# -------------------------------------------------------------------
function ConvertTo-HumanReadable
{
    param (
        [Parameter(Mandatory = $true)] [int64]$Bytes,
        [int]$DecimalDigits = 2
    )

    $units = @("B", "KB", "MB", "GB", "TB", "PB")
    $unitIndex = 0

    if ($Bytes -eq 0)
    {
        return "0 B"
    }

    # we use a float variable so it keeps fractional part
    [float]$value = $Bytes

    while ([Math]::Abs($value) -ge 1024 -and $unitIndex -lt $units.Length - 1)
    {
        $value /= 1024
        $unitIndex++
    }

    $formattedResult = "{0:N$($DecimalDigits)} {1}" -f $value, $units[$unitIndex]
    return $formattedResult
}


function Move-FolderWithProgress
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    # Ensure the source exists
    if (-not (Test-Path -Path $SourcePath -PathType Container))
    {
        Write-Error "Source folder '$SourcePath' does not exist or is not a folder."
        return
    }

    # Ensure the destination is ready
    if (-not (Test-Path -Path $DestinationPath))
    {
        # NOTE: this will reset NTFS perms but they are reset anyway on a move between disks
        New-Item -ItemType Directory -Path $DestinationPath | Out-Null
    }

    # Get the total size of all files in the source folder
    Write-Host "Calculating size of source folder: " -NoNewline
    $files = Get-ChildItem -Path $SourcePath -Recurse -File
    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
    Write-Host (ConvertTo-HumanReadable -Bytes $totalSize) -ForegroundColor Cyan

    if ($totalSize -eq 0)
    {
        Write-Error "No files to move in '$SourcePath'."
        return
    }

    $bytesTransferred = 0

    foreach ($file in $files)
    {
        # Calculate the destination path for the file
        $relativePath = $file.FullName.Substring($SourcePath.Length).TrimStart('\')
        $destFilePath = Join-Path -Path $DestinationPath -ChildPath $relativePath

        # Ensure the destination directory exists
        $destDirectory = Split-Path -Path $destFilePath
        if (-not (Test-Path -Path $destDirectory))
        {
            # NOTE: this will reset NTFS perms but they are reset anyway on a move between disks
            New-Item -ItemType Directory -Path $destDirectory | Out-Null
        }

        # Copy the file
        Copy-Item -Path $file.FullName -Destination $destFilePath

        # Update progress
        $bytesTransferred += $file.Length
        $percentComplete = [math]::Round(($bytesTransferred / $totalSize) * 100, 2)

        $done = ConvertTo-HumanReadable -Bytes $bytesTransferred
        $sum = ConvertTo-HumanReadable -Bytes $totalSize

        Write-Progress -Activity "Reloc8ing Files" -Status "$done of $sum [$percentComplete% complete]" -CurrentOperation $destFilePath -PercentComplete $percentComplete
    }

    # Remove the source folder after copying
    Remove-Item -Path $SourcePath -Recurse -Force

    Write-Progress -Activity "Reloc8ing Files" -Status "Complete" -Completed
    Write-Output "Folder successfully moved from '$SourcePath' to '$DestinationPath'."
}



# If src not provided as cmd line argument, show folder selection dialog
if (-not $src)
{
    Write-Host "No source folder provided. Opening GUI for folder selection..." -ForegroundColor Yellow

    $src = Select-Folder -Description "Select the source folder (the one to be moved)"
    if (-not $src)
    {
        Write-Host "Error: No source folder selected." -ForegroundColor Red
        exit 1
    }
    
}

Write-Verbose "Testing source path: $src"

# verify source folder
try
{
    # does it exist?
    if (-not (Test-Path -Path $src -PathType Container))
    {
        # very unlikely to get here unless they provided the src path on the command line
        Write-Host "Error: No such source folder '$src'." -ForegroundColor Red
        exit 1
    }

    # Verify source is not a junction, symlink, etc
    $srcAttributes = (Get-Item $src).Attributes
    if ($srcAttributes -band [System.IO.FileAttributes]::ReparsePoint)
    {
        # TODO: should we just keep following the reparse points and then automatically or offer to move the resulting folder?
        Write-Host "Error: The source folder '$src' is a reparse point (e.g. a junction or symlink)." `
            -ForegroundColor Red
        exit 1
    }
}
catch
{
    Write-Host "Unknown error with source folder: '$src' - $_" -ForegroundColor Red
    exit 1
}


# If dst not provided as cmd line argument, show folder selection dialog
if (-not $dst)
{
    if ($ChooseDestPath)
    {
        $dst = Select-Folder -Description "Select a folder to move the source folder into`n(or an empty folder to move the source contents into)"
    }
    else
    {
        # just select a destination drive (as they didn't use -ChooseDestPath)
        $srcDrive = Split-Path -Path $src -Qualifier
        $dstDrive = Select-NTFSDrive -Exclude $srcDrive

        if ($null -eq $dstDrive)
        {
            Write-Host "No destination drive selected.  Exiting." -ForegroundColor Red
            exit 1
        }

        $reloc8dFolder = "${dstDrive}\$defaultDstPath"

        $dst = Join-Path -Path $reloc8dFolder -ChildPath ("\$(Split-Path -Path $src -Leaf )" )

        # now, create the directory if necessary
        if (-not (Test-Path -Path $reloc8dFolder))
        {
            Write-Host "Creating reloc8d folder: $reloc8dFolder..." -ForegroundColor Magenta
            New-Item -Path $reloc8dFolder -ItemType Directory -Force
        }
    }

    if (-not $dst)
    {
        Write-Host "No destination folder selected. Exiting." -ForegroundColor Red
        exit 1
    }
}


Write-Verbose "Testing destination folder: $dst"

if (Test-Path -Path $dst)
{
    # path already exists, we'll try to move source to a subfolder of this path..
    try
    {
        $dstItem = Get-Item $dst
        $dstAttributes = $dstItem.Attributes
        
        if ($dstAttributes -band [System.IO.FileAttributes]::ReparsePoint)
        {
            Write-Host "Destination folder '$dst' is a junction/symlink. Removing..." -ForegroundColor Yellow
            $dstItem.Delete()   # deletes just the junction link file without prompt

            #FIXME: C:\one => D:\one => C:\two
            # starting the process of linking C:\two back to D:\one would delete D:\one link and C:\one stops working
        }
        elseif (-not (Test-Path -Path $dst -PathType Container))
        {
            Write-Host "Destination '$dst' already exists but isn't a folder.  Exiting..." -ForegroundColor Red
            exit 1
        }
        else   
        {
            $contents = Get-ChildItem $dst

            if ($null -ne $contents -and $contents.Count -gt 0)
            {
                # they selected a non-empty folder

                $srcFolderName = Split-Path -Path $src -Leaf
                $newDst = Join-Path -Path $dst -ChildPath "/$srcFolderName"

                if (-not (Test-Path -Path $newDst))
                {
                    $title = "Non-empty destination folder"
                    $message = @"
Destination folder ($dst) is not empty.
Do you want to move the source to a folder inside this one named $srcFolderName
(i.e. $newDst)?
"@
                    $result = [System.Windows.Forms.MessageBox]::Show($message, $title, [System.Windows.Forms.MessageBoxButtons]::YesNo)

                    if ($result -ne [System.Windows.Forms.DialogResult]::Yes)
                    {
                        Write-Host "Exiting." -ForegroundColor Red
                        exit 1
                    }
                    $dst = $newDst
                }
                else
                {
                    # they selected a destination folder that already has a folder inside with the same name as the source

                    $newDstItem = Get-Item $newDst
                    $newDstAttributes = $newDstItem.Attributes
                    
                    if ($newDstAttributes -band [System.IO.FileAttributes]::ReparsePoint)
                    {
                        Write-Host "Implied destination folder '$newDst' is a junction/symlink. Removing..." -ForegroundColor Yellow
                        $newDstItem.Delete()   # deletes just the junction link file without prompt
                        $dst = $newDst
                    }
                    else 
                    {
                        Write-Host "Error: Destination folder '$dst' exists and already has a '$srcFolderName' subfolder. Exiting." -ForegroundColor Red
                        exit 1
                    }
                }
            }
            else
            {
                # they selected an empty folder.  delete it ready to move
                # source into its place.
                #
                # FIXME: this probably should be done later
                # but what's the harm of deleting an empty folder?
                Remove-Item -Path $dst
            }
        }
    }
    catch
    {
        Write-Host "Unknown error with destination folder: '$dst' - $_" -ForegroundColor Red
        exit 1
    }
}
else 
{
    # dst doesn't exist atm 
    # (this must have been specified as cmd line argument or it was constructed using $defaultDstPath)
    # test we can create it first
    try
    {
        New-Item -Path $dst -ItemType Directory -Force | Out-Null
        Remove-Item -Path $dst
    }
    catch
    {
        Write-Host "Error creating $dst : $_" -ForegroundColor Red
        exit 1
    }
}


Write-Host "Source: $src"
Write-Host "Destination: $dst"
Write-Host

# prevent attempts to reloc8 a folder into one of its subfolders
# e.g. C:\Games\Fortnite into C:\Games\Fortnite\SubDir

# Check if $dst is a subfolder of $src
if ([System.IO.Path]::GetFullPath($dst) -like ([System.IO.Path]::GetFullPath($src) + "\*")) 
{
    Write-Output "Error: Cannot move $src into a subfolder of itself!" -ForegroundColor Red
    exit 1
}


if (-not $Force)
{   
    Write-Host "All seems good" -ForegroundColor Yellow
    Read-Host -Prompt "Press Enter if happy"
}


# Move the folder
Write-Host "Moving folder from '$src' to '$dst'..." -ForegroundColor Cyan

try
{
    # Move the folder, -Force = without asking for user confirmation
    #Move-Item -Path $src -Destination $dst -Force -Verbose

    Move-FolderWithProgress -SourcePath $src -DestinationPath $dst
    Write-Host "Move successful."
}
catch
{
    Write-Host "Error moving folder - $_" -ForegroundColor Red
    exit 1
}

# Create NTFS junction
# (like mklink /J $src $dst)
Write-Host "Creating NTFS junction: '$src' ==> '$dst' ..." -ForegroundColor Cyan

try
{
    New-Item -Path $src -ItemType Junction -Target $dst | Out-Null
}
catch
{
    Write-Host "Error creating NTFS junction: $_" -ForegroundColor Red
    exit 1
}

Write-Host "Folder reloc8d successfully." -ForegroundColor Green