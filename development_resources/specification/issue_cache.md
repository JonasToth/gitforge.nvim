# Spec: Issue Persistence and Caching

**Issue Persistence** is about providing a local file for _interesting_/_pinned_ issues. These issues
may be accessed at any point in time, even without network connection. Persisted issues outlive
a single `nvim` session.
**Issue Caching** is similar to persistence but only during a single `nvim` session. The goal
of caching is to avoid lag from network access to the git forge api.

Viewing a single issue happens in the following order:
1. Read the issue from the volatile cache (== a nvim buffer)
1. Fall back to the persistent cache (== a local file)
1. Fall back to network access

After an issue is opened, an asynchronous issue update is always triggered to get the latest version
from the git forge. The update is written through the volatile cache and optionally to the
persistent cache.

## Requirements

### Necessities

- the caching must provide a snappy user interface. Lag for displaying an issue that was already
  loaded before shall not occur
- an issue can be marked as _pinned_ which means it shall be persisted
- the issue cache differentiates between projects
    - the "primary key" is likely "owner__project__issue_number"
- working with at least persisted issues must still work during interrupted connectivity to the
  git forge (lack of network, downtime of the forge)
- the [issue list](issue_list.md) must still work with the cached/persisted issues

### Nice to Have

- periodic issue updates with subsequent write-through to the persistent cache
- persisted issue are automatically loaded into buffers on start

## Non-Functional Requirements

- caching should be an implementation detail user don't have to worry about

## Customizations

- directory path for the persistent cache, by default in `nvim-data`
