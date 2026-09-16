# Native counting limitations

These probes were separate from the timing series and did not operate a Firstmate home or vendor session.
No privilege escalation or installation was attempted.
The successful packet uses explicitly partial Bash attribution instead.

## Windows process-start subscription

Command:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -Command 'try { Register-CimIndicationEvent -Query "SELECT * FROM Win32_ProcessStartTrace" -SourceIdentifier WayfinderBaselineProbe -ErrorAction Stop | Out-Null; Unregister-Event -SourceIdentifier WayfinderBaselineProbe; "available" } catch { "unavailable: " + $_.Exception.Message }'
```

Observed output:

```text
unavailable: Access denied
```

No workload was launched under this unavailable observer.

## Installed strace control

Version: `strace (cygwin) 3.6.10`.
Its help reports child tracing and Windows debug events enabled by default; `-f` is a toggle, not an unconditional enable.
The probe used the `minimal+inherit` mask rather than startup environment dumping.

Command, with the task-owned output directory abbreviated:

```bash
strace --mask=minimal+inherit --output="$OWNED_OUTPUT/control.log" \
  /usr/bin/bash -c 'node -e "process.stdout.write(\"owned-native-control\\n\")"'
```

The invoking shell reported a segmentation fault for this command.
The trace contained the following terminal debug event:

```text
--- Process 26972 exited with status 0xc0000005
```

The intended successful native-control output was not produced.
This is an unavailable counting method, not a count of a Firstmate workflow or evidence of a Firstmate product crash.
It was not used for the timing series or retried against a live process.
