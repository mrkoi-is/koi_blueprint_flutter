"""Non-blocking, process-owned lock for blueprint test operations."""
from contextlib import contextmanager
import errno
import os
from pathlib import Path


class WorkspaceBusy(ValueError):
    pass


@contextmanager
def workspace_lock(root: Path):
    path = Path(root).resolve() / 'build' / 'blueprint-test.lock'
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a+b') as stream:
        if os.name == 'nt':
            import msvcrt
            # Lock one permanent byte: never unlink the file while in use.
            if path.stat().st_size == 0:
                stream.write(b'\0')
                stream.flush()
            stream.seek(0)
            try:
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError as error:
                if error.errno in (errno.EACCES, errno.EAGAIN, errno.EDEADLK):
                    raise WorkspaceBusy(f'workspace_busy: {root}') from error
                raise
            try:
                yield
            finally:
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            try:
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as error:
                if error.errno in (errno.EACCES, errno.EAGAIN):
                    raise WorkspaceBusy(f'workspace_busy: {root}') from error
                raise
            try:
                yield
            finally:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
