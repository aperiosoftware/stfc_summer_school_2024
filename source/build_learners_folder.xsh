#!/bin/env xonsh
"""
Convert a set of notebooks into an instructor/learner pair.

The learner notebooks will have all the code stripped from the code cells unless
they have "keep-inputs" in their tags.
"""
import sys
import argparse
from pathlib import Path

import yaml
import nbformat


def strip_code_cells(input_notebook, output_notebook):
    with open(input_notebook) as fp:
        raw_notebook = nbformat.read(fp, as_version=4)

    for i, cell in enumerate(raw_notebook.get("cells")):
        if cell.cell_type == "code" and "keep-input" not in cell.metadata.get("tags", []):
            cell.source = []
        # Make the id predictable to reduce diffs
        cell["id"] = str(i)

    with open(output_notebook, "w") as fp:
        nbformat.write(raw_notebook, fp)


def get_first_h1(markdown_file):
    with open(markdown_file) as fobj:
        for line in fobj.readlines():
            if line.startswith("# "):
                return line.split("# ")[1].strip()
    return ""


def build_toc_links(toc_files):
    titles = {}
    for name, (source, instructor, learner) in toc_files.items():
        titles[name] = get_first_h1(source)

    links = []
    for name, title in titles.items():
        _, instructor, learner = toc_files[name]
        links.append(f"[{title}]({str(learner)}) - [Instructor]({str(instructor)})")

    return "\n".join([f"1. {link}" for link in links])


def add_toctree_to_index(toc_files, input_notebook, output_notebook):
    with open(input_notebook) as fp:
        raw_notebook = nbformat.read(fp, as_version=4)

    for cell in raw_notebook.get("cells"):
        if "toc" in cell.metadata.get("tags", []):
            cell.source = build_toc_links(toc_files)

    with open(output_notebook, "w") as fp:
        nbformat.write(raw_notebook, fp)


argp = argparse.ArgumentParser(description=__doc__)
argp.add_argument("base_dir", nargs=1, help="path to the root of the repo to convert")
argp.add_argument("output_dir", nargs=1, help="path to the destination directory")
argp.add_argument("-t", "--tutorial-dir",
                  action="store", default="tutorial",
                  help="subdirectory in the repo where the jupyter book project lives")
argp.add_argument("--index", nargs=1, action="store",
                  help="A template notebook to use as an index.")
argp.add_argument("-c", "--copy", nargs="*", action="append",
                  help="Any additional files to copy into the output_dir")
argp.add_argument("-s", "--skip", nargs="*", action="append",
                  help="Any notebook files to skip")

args = argp.parse_args(sys.argv[1:])

base_dir = Path(args.base_dir[0])
output_dir = Path(args.output_dir[0])

# Make the output dir
output_dir.mkdir(exist_ok=True)

files = base_dir.glob("*.ipynb")

# For each file in the toc tree make an instructor notebook, then make a learner
# notebook without the source cells.
toc_files = {}
for nb in files:
    if args.skip:
        if any([nb in f[0] for f in args.skip]):
            continue

    input_file = nb
    if not input_file:
        raise ValueError(f"File {nb} not found")
    instructor_file = output_dir
    instructor_file.mkdir(exist_ok=True)
    instructor_file /= (input_file.stem + "_worked.ipynb")
    learner_file = output_dir / (input_file.stem + ".ipynb")
    toc_files[nb] = (input_file,
                     instructor_file.relative_to(output_dir),
                     learner_file.relative_to(output_dir))

    $[jupytext --to ipynb @(input_file) -o @(instructor_file)]
    $[jupyter nbconvert --clear-output --inplace @(instructor_file)]
    print(f"[learner] transforming {instructor_file} to {learner_file}")
    strip_code_cells(instructor_file, learner_file)

# Copy all files / directories provided with --copy
if args.copy:
    for fname in args.copy:
        fname = fname[0]
        print(f"[copy] Copying {fname} to output_dir")
        $[cp -r @(base_dir / fname) @(output_dir / fname)]

# Put a rendered toctree in the index notebook
if args.index:
    input_index = base_dir / args.index[0]
    print(f"[index] Rendering toctree in {input_index}")
    output_notebook = output_dir / "index.ipynb"
    add_toctree_to_index(toc_files, input_index, output_notebook)
