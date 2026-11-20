"""Plan workspace generators from the package resolution produced by Pub."""
from graphlib import CycleError, TopologicalSorter
import json
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.request import url2pathname


def _packages(path):
    try:
        records = json.loads(path.read_text(encoding='utf-8'))['packages']
        if not isinstance(records, list):
            raise ValueError('expected a packages list')
        packages = {}
        for record in records:
            name = record['name']
            if not isinstance(name, str) or not name or name in packages:
                raise ValueError(f'invalid or duplicate package name: {name!r}')
            packages[name] = record
        return packages
    except (OSError, KeyError, TypeError, ValueError) as error:
        raise ValueError(f'Cannot read {path}: {error}. Run blueprint.py check bootstrap.') from error


def generation_plan(root, workspace):
    """Return (active member path, uses build_runner) pairs in dependency order."""
    if not workspace:
        return []
    root = Path(root).resolve()
    config_path = root / '.dart_tool/package_config.json'
    paths = {member.resolve() for member in workspace}
    names = {}
    for name, record in _packages(config_path).items():
        uri = record.get('rootUri')
        if not isinstance(uri, str) or not uri:
            raise ValueError(f'Invalid rootUri for {name} in {config_path}')
        resolved = urlsplit(urljoin(config_path.as_uri(), uri))
        if resolved.scheme != 'file':
            continue
        host = resolved.netloc
        location = f'//{host}{resolved.path}' if host and host.lower() != 'localhost' else resolved.path
        path = Path(url2pathname(location)).resolve()
        if path in paths:
            if path in names:
                raise ValueError(f'Multiple packages resolve to workspace member {path} in {config_path}')
            names[path] = name
    local = {}
    for member in workspace:
        name = names.get(member.resolve())
        if not name or name in local:
            raise ValueError(f'Workspace member {member} does not match {config_path}. Run blueprint.py check bootstrap.')
        local[name] = member

    graph_path = root / '.dart_tool/package_graph.json'
    edges = {}
    for name, record in _packages(graph_path).items():
        deps = record.get('dependencies')
        dev = record.get('devDependencies', []) if name in local else []
        if not isinstance(deps, list) or not isinstance(dev, list) or not all(isinstance(d, str) for d in deps + dev):
            raise ValueError(f'Invalid dependencies for {name} in {graph_path}')
        edges[name] = deps + dev

    sorter = TopologicalSorter({name: () for name in local})
    for name in local:
        if name not in edges:
            raise ValueError(f'Workspace member {name} missing from {graph_path}. Run blueprint.py check bootstrap.')
        # An external dependency can itself consume a workspace package. Walk
        # through external packages, including external-only cycles, but never run them.
        pending = edges[name].copy()
        visited, prerequisites = set(), set()
        while pending:
            dependency = pending.pop()
            if dependency not in edges:
                raise ValueError(f'Dependency {dependency} missing from {graph_path}. Run blueprint.py check bootstrap.')
            if dependency in local:
                prerequisites.add(dependency)
            elif dependency not in visited:
                visited.add(dependency)
                pending.extend(edges[dependency])
        sorter.add(name, *sorted(prerequisites))
    try:
        return [(local[name], 'build_runner' in edges[name]) for name in sorter.static_order()]
    except CycleError as error:
        cycle = ' -> '.join(error.args[1])
        raise ValueError(f'Workspace code generation dependency cycle: {cycle}') from error
