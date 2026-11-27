"""Reject duplicate YAML keys and malformed embedded Bash in release workflows."""
from pathlib import Path
import subprocess
import yaml

class UniqueLoader(yaml.SafeLoader):
    pass

def mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise ValueError(f"duplicate YAML key {key!r} at line {key_node.start_mark.line + 1}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result

UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)
for path in (Path(".github/workflows/release.yml"), Path(".github/workflows/version-release.yml")):
    data = yaml.load(path.read_text(), Loader=UniqueLoader)
    assert isinstance(data.get("jobs"), dict) and data["jobs"], path
    for name, job in data["jobs"].items():
        if "uses" in job:
            continue
        assert job.get("steps"), f"{path}: empty job {name}"
        for step in job["steps"]:
            run = step.get("run")
            if not run or step.get("shell") != "bash":
                continue
            subprocess.run(["bash", "-n"], input=run, text=True, check=True)
    print(f"{path}: duplicate-key and explicit Bash syntax checks passed")
