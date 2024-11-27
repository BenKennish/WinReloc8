<#
WinReloc8
   A PowerShell script by Ben Kennish (ben@kennish.net)

Allows easily relocating a folder from one location on a hard disk to another (e.g. 
on a different hard disk), creating a redirecting 'junction' which means that 
any app that is set up to find the folder in the original location will still 
work fine.

Technical info: the existing location of the folder must be on an NTFS 
formatted partition
#>
param (
    [string]$src,
    [string]$dst
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
Add-Type -AssemblyName System.Windows.Forms


# Display a folder selection dialog
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

# If src not provided as cmd line argument, show folder selection dialog
if (-not $src)
{
    Write-Host "No src provided. Opening GUI for folder selection..." -ForegroundColor Yellow

    $src = Select-Folder -Description "Select where the game is now:"
    if (-not $src)
    {
        Write-Host "Error: No source folder selected." -ForegroundColor Red
        exit 1
    }
    
}

Write-Host "Source folder: $src"

# verify source folder
try
{
    # does it exist?
    if (-not (Test-Path -Path $src -PathType Container))
    {
        # very unlikely to occur if they used the GUI but you never know
        Write-Host "Error: No such source folder '$src'." -ForegroundColor Red
        exit 1
    }

    # Verify source is not a junction
    # TODO: check it's not a sym link or anything else funky
    $srcAttributes = (Get-Item $src).Attributes
    if ($srcAttributes -band [System.IO.FileAttributes]::ReparsePoint)
    {
        Write-Host "Error: The source folder '$src' is a junction." -ForegroundColor Red
        exit 1
    }
}
catch
{
    Write-Host "Error checking source folder: '$src' - $_" -ForegroundColor Red
    exit 1
}

# If dst not provided as cmd line argument, show folder selection dialog
if (-not $dst)
{
    $dst = Select-Folder -Description "Select an empty folder where you want the game to be:"
    if (-not $dst)
    {
        Write-Host "No destination folder selected. Exiting." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Destination folder: $src"

# verify destination folder
if (Test-Path -Path $dst)
{
    try
    {
        $dstItem = Get-Item $dst
        $dstAttributes = $dstItem.Attributes
        if ($dstAttributes -band [System.IO.FileAttributes]::ReparsePoint)
        {
            Write-Host "Destination folder '$dst' is a junction. Removing..." -ForegroundColor Yellow
            $dstItem.Delete()  # this deletes just the junction and not what it is linking to
        }
        else
        {
            $contents = Get-ChildItem $dst

            if ($null -eq $contents)
            {
                Write-Host '$contents is $null'
            }
            else
            {
                Write-Host "`$contents has type $($contents.GetType().FullName)"
            }

            if ($null -ne $contents -and $contents.Count -gt 0)
            {
                # they selected a non-empty folder

                $sourceFolderName = Split-Path -Path $src -Leaf
                $newDst = Join-Path -Path $dst -ChildPath "/$sourceFolderName"

                if (-not (Test-Path -Path $newDst))
                {
                    $title = "Non-empty destination folder"
                    $message = "Destination folder ($dst) is not empty.`nDo you want to move the source to a folder inside this one named $sourceFolderName`n(i.e. $newDst)?"
                    $result = [System.Windows.Forms.MessageBox]::Show($message, $title, [System.Windows.Forms.MessageBoxButtons]::YesNo)

                    if ($result -ne [System.Windows.Forms.DialogResult]::Yes)
                    {
                        Write-Host "Error: Destination folder '$dst' exists and isn't empty. Exiting." -ForegroundColor Red
                        exit 1
                    }
                    $dst = $newDst
                }
                else
                {
                    Write-Host "Error: Destination folder '$dst' exists, isn't empty, and already has a '$sourceFolderName' subfolder.  Exiting." -ForegroundColor Red
                    exit 1
                }
            }
            else
            {
                # they selected an empty folder.  delete it ready to move source into place
                # NB: this helps as we can potentially preserve the NTFS permissions of the root folder
                Remove-Item -Path $dst
            }
        }
    }
    catch
    {
        Write-Host "Error checking destination folder: '$dst' - $_" -ForegroundColor Red
        exit 1
    }
}
else 
{
    # dst doesn't exist atm
    # test we can create it first
    try
    {
        New-Item -Path $src -ItemType Directory -Force | Out-Null
        Remove-Item -Path $src 
    }
    catch
    {
        Write-Host "Error creating $src : $_" -ForegroundColor Red
        exit 1
    }
}


# prevent attempts to relocate  C:\Games\Fortnite to C:\Games\Fortnite\SubDir
$srcFullPath = (Resolve-Path -Path $src).ProviderPath
$dstFullPath = (Resolve-Path -Path $dst).ProviderPath

if ($dstFullPath.StartsWith("$srcFullPath\", [System.StringComparison]::OrdinalIgnoreCase))
{
    Write-Host "You cannot move the source folder into a subfolder of itself" -ForegroundColor Red
    exit 1
}


# Move the folder
# TODO: add a nice progress bar, preferably based on % of bytes rather than files
Write-Host "Moving folder from '$src' to '$dst'..." -ForegroundColor Cyan

try
{
    # Move the folder
    Move-Item -Path $src -Destination $dst -Force -Verbose
    Write-Host "Move successful."
}
catch
{
    Write-Host "Error moving folder - $_" -ForegroundColor Red
    exit 1
}

# Create NTFS junction
# like mklink /J $src $dst
Write-Host "Creating NTFS junction at '$src' pointing to '$dst'..." -ForegroundColor Cyan

try
{
    New-Item -Path $src -ItemType Junction -Target $dst | Out-Null
}
catch
{
    Write-Host "Error creating NTFS junction: $_" -ForegroundColor Red
    exit 1
}

Write-Host "Operation completed successfully." -ForegroundColor Green