# Testacular, testacular!

### Problem:
"Testacular start" creates a persistent host which real devices can be hooked up to.
To let these devices run some tests in a CI environment there is the "testacular run" command.

This works great but if you have some devices which you want to use for several testacular configs,
one for each CI build, you must either set up several testacular hosts which can be cumbersome.

### Solution:
The following scripts enables a shared Testacular host process to which each CI build can queue 
test runs to. 


## Start-Host.ps1

Starts a Testacular placeholder host on a given port which does not include any tests.
It is just using an empty config just to make sure devices can hook up to the host.

Start this in a scheduled task when the server boots to start the host process.
If you have installed Testacular with "npm -g install testacular" you will be just fine by starting it without options:

```powershell
.\Start-Host.ps1
```

## Queue-Run.ps1

Queues a "single-run" on the devices that are hooked up to the placeholder host.
This is done by killing the placeholder host and starting a new host with the testacular config specified for this run.

Call this script from the CI job - with the testacular config to be run - to queue it to the host process.
Example:

```powershell
Queue-Run.ps1 c:\ci\build\app\testacular.conf.js
```

The output from testacular will be sent to the output of this command.
Example:

```
Run 36 is waiting for available executor
Run 36 status: RUNNING
Run 36 status: FAILED
Output:
    Run 36 started at 01/09/2013 19:02:46 in C:\src\testaculartestacular\runs\36
    Killing default host (PID: 5464)
    Waiting for default host to exit (PID: 5464)
    Starting run with config C:\ci\build\app\testacular.conf.js
    Waiting for run to complete (PID: 2412)
    info: Testacular server started at http://localhost:8080/
    info (IE 9.0): Connected on socket id W4NRupj-q54E2IadVhPe
    IE 9.0 WorkorderList should have a dependentObservable FAILED
        ReferenceError: 'console' is undefined
    IE 9.0: Executed 1 of 131 (1 FAILED) (skipped 8)
```

## The Workspace

The scripts stores the state of each run in a directory, which can be overridden as an option to the scripts.
The directory will contain a file called nextRunNumber and a sub-directory with one directory per run.

The config being run will not be copied to this directory - its only purpose is to let the 
scripts keep track of the state for each run. These directories can be removed after the test run is completed.

Each directory contain the following files:
* status - the current status of the run
* testacular.out.log - stdout of testacular
* testacular.out.log - stderr of testacular
* output - the output displayed when calling Queue-Run.ps1
