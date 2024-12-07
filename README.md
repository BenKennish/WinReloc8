# WinReloc8

## Description

Easily move a folder from one hard disk location to another (possibly on a
different drive), creating a redirecting 'junction' in the old location so that
any app that expects to find the folder in the original location will still
work fine. Useful for moving any large apps around (esp. video games)
when running low on disk space on one drive with plenty of space on another.

## Technical Info

Before it is relocated, the folder must be on an NTFS formatted partition (the most common format used by modern versions of Windows).

## Installation

_TODO_

## Configuration

_TODO_

## Command Line Arguments

WinReloc8.ps1 _[srcPath]_ _[dstPath]_  -Force

-Force
   Start without prompting to check details


### Description

_src_ and _dst_ are the source and destination paths. If you don't provide one
or both of them, WinReloc8 will prompt you using a GUI "FolderBrowserDialog"

### Examples

WinReloc8.ps1 C:\Games\Fortnite D:\Games\Fortnite

WinReloc8.ps1 C:\Games\Fortnite

WinReloc8.ps1
