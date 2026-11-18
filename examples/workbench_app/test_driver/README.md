# AI-only Workbench entry

`ai_main.dart` starts the real Workbench launcher with the Driver extension and
an isolated storage fixture. The production `lib/main.dart` is unchanged. Use
only on a local debug session. The first log line contains `KOI_AI_SANDBOX`,
its 32-character ID and location. A fresh ID is generated unless one is passed:

The debug binding combines Workbench's exit mixin with the public
`FlutterDriverExtension` service. The standard Driver initializer creates its
own private binding and therefore cannot be called after Workbench's binding.

```sh
flutter run -d chrome -t test_driver/ai_main.dart \
  --dart-define=KOI_AI_RUN_ID=0123456789abcdef0123456789abcdef
```

Reusing exactly the same ID on the same platform and origin reopens its saved
content after the first app has stopped and released the workspace lock. This is
a test fixture, not a production workspace. IDs must contain exactly 32 lower
case hexadecimal characters; native storage is limited to the system temporary
directory under `koi_ai_<id>`, and Web storage to IndexedDB `koi_ai_<id>`.

After stopping all app processes and finishing the experiment, delete only the
specific printed `koi_ai_<id>` temporary directory, or use the browser's
application storage inspector to delete only the printed IndexedDB name. The
fixture intentionally remains after exit so restart tests can read it. Automatic
or blanket cleanup would erase evidence and must not target normal workspaces.

## Managed POSIX debug session

For a locally launched Flutter process, the workspace helper can retain its
process session and logs and stop its owned processes without looking up a PID:

```sh
python3 tool/ai_session.py start --workspace . --cwd apps/my_app \
  --run-id 0123456789abcdef0123456789abcdef --storage koi_ai_0123456789abcdef0123456789abcdef \
  -- flutter run --no-pub --machine -d macos -t test_driver/ai_main.dart \
  --use-application-binary=build/macos/Build/Products/Debug/my_app.app
python3 tool/ai_session.py stop --session <returned-session-directory>
```

Prepare the debug app first with the intended `KOI_AI_RUN_ID` dart-define,
then use the actual member path, app bundle, and pinned Flutter executable.
The ID is compiled into the prebuilt app: verify `KOI_AI_SANDBOX` in the log
before using it. A build can launch Xcode services that detach from the process
session; these must not be killed by the helper and make the stop check fail.
`--no-build` alone still invoked an incremental Xcode build in local tests;
the explicitly prebuilt application avoided it.
The returned directory contains `session.json`, `stdout.log` and `stderr.log`.
The helper requests Flutter's normal quit first, then terminates remaining
processes in its own OS session after a grace period. It never deletes storage.
Check the printed sandbox identifier and reopen it in a second managed session
to verify the lock was released and the content actually persisted. A stopped
process session alone does not prove the storage or UI result.

For Dart MCP, take the URI from the `app.dtd` event in `stdout.log`, call the
MCP `dtd` tool with `connect`, then inspect and interact with the app. The
helper sends the Flutter machine protocol's `app.stop` request during stop.
Wait for the UI's saved status before stopping, then use MCP to read the
content after reopening; seeing `app.stop` succeed is not persistence proof.

This helper does not adopt an app launched independently by Dart MCP, and
cannot control descendants that deliberately escape the owned OS session.
Do not claim an MCP stop/restart passed solely because this helper stopped an
independently launched app. Windows session management is not implemented.
Chrome hot restart is currently not a supported verification path; use a new
session and explicitly verify content after reopening instead.
