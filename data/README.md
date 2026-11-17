# data/ — where the data goes

**The contents of this folder are not tracked by Git.** Real data may contain personal information, so do not copy it to Git or to the cloud (how this is enforced: see [`docs/WORKSPACE.md`](../docs/WORKSPACE.md) §3).

| Folder | Contents | Who writes it |
|---|---|---|
| `raw/` | Data exactly as received. **Do not modify** (the starting point for reproduction) | A person |
| `raw/dummy/` | Dummy data whose column names, types and missingness distribution resemble the real data (see below) | A person |
| `interim/` | Intermediate data (joins, type conversions, etc.) | Analysis code |
| `processed/` | Data used directly in the analysis | Analysis code |
| `external/` | Reference data brought in from outside (regional statistics, code tables, etc.) | A person |

**Prepare the dummy data yourself** (the template has no way of making it). Write how you made it in `CHANGELOG.md`. Write which data a run uses as `data.mode` in the config (`dummy`, `production`, etc.; it is recorded: see [`docs/REPRODUCIBILITY.md`](../docs/REPRODUCIBILITY.md) §1).
