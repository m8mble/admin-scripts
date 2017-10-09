Admin Scripts
================

This repository contains helpers for administrative duty.
Each directory is attributed to a different task.


Backup
--------

First things first: backups.
`make_snapshots.sh` is a swiss army knife like tool for managing automatic backup of data.
It creates rotating, hard link based snapshots with `rsync`.
For automation it should be called as `cron` job in appropriate intervals.

Configuration can easily be done in `bash`.
There is a sample config `config.sh.sample` for the basics and a more advanced `config.selection.sample`
(explaining an versatile mechanism of creating monthly snapshots based on a config for daily ones).
