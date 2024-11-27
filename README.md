# WinReloc8

## Description

Allows easily relocating a folder from one location on a hard disk to another
(e.g. on a different hard disk), creating a redirecting 'junction' which means
that any app that is expecting to find the folder in the original location will
still work fine. Useful for moving any large apps around (esp. video games)
when running low on disk space on one drive with plenty of space on another.

## Technical Info

Before it is relocated, the folder must be on an NTFS formatted partition (the most common format used by modern versions of Windows).

## Installation

_TODO_

## Configuration

_TODO_

## Command Line Arguments

WinReloc8.ps1 _[src]_ _[dst]_

_src_ and _dst_ are the source and destination paths. If you don't provide one
or both of them, WinReloc8 will prompt you using a GUI "FolderBrowserDialog"
