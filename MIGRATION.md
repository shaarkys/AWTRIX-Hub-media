# Consolidation on 2026-10-25

| Original location under the GitHub workspace | Current location in this repository |
| --- | --- |
| `SolarApp-extension/` | `SolarApp/` |
| `com.haassohn.pellets/docs/awtrixng/` | `PelletStove/` |
| `AWTRIX-Hub-media/` publication assets | Existing `SolarApp/` and `PelletStove/` media directories |
| Sibling `AWTRIX-Hub-media.zip` | `dist/AWTRIX-Hub-media.zip` |

The initial public commit `4096c95` saved a 194-file recovery snapshot before reorganization or cleanup. The snapshot contains the full original app folders, current and historical media, generator inputs, captures and earlier ZIPs. Check its companion SHA-256 inventory before restoring individual files. Do not overwrite active sources with older archived versions accidentally.

All four installable scripts are migrated without changing their bytes: three matching SolarApp files and the latest PelletStove file, including standby temperature turns and the gated fault-clear fix. Historical SolarApp revisions and obsolete approximate-font media are retained in the recovery ZIP rather than duplicated as active files.

The PelletStove verifier uses a frozen capability/unit/range contract instead of reading a neighboring Homey checkout. The central build generates fresh captures from the committed test harnesses and current scripts, without stale source copies from `work/`. Source hashes are relative to the repository; the media-only ZIP is rebuilt inside `dist/`.

## Guarded removal of the old copies

After the consolidated commit has been reviewed, committed and pushed:

```powershell
./tools/cleanup-migration.ps1
./tools/cleanup-migration.ps1 -Execute
```

The first command is read-only. Both verify that the recovery ZIP matches its committed hash, the GitHub `main` ref matches the current local commit, and the active working tree is clean. Before any removal, they check both old directories in full against the snapshot manifest and reject extra, missing or modified files, symlinks and junctions. `-Execute` then removes only the verified old app folders and unchanged sibling ZIP. It never modifies the Homey app's source or unrelated working-tree edits.

The original generated `work/` tree is also recoverable from the snapshot. Current `work/` data is disposable: the repository build recreates it from active sources. Keep it ignored by Git.

## Scope and evidence

This is an organization and reproducibility change. App MQTT topics, configuration IDs, runtime logic and publication pixels are preserved. Offline verification covers both Berry logic suites, generation, font metrics, input contracts, drawing captures and decoded GIF frames. No live broker, stove, clock, Homey Flow or AWTRIX Hub publishing is part of this migration.
