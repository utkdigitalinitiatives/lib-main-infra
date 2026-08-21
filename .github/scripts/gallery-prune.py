#!/usr/bin/env python3
"""Prune stale image versions from lib_main_gallery.

Nothing else prunes this gallery. Builds publish ~17 versions a month and every
one of them is kept forever, so the gallery grew to 103 versions of which 3 were
actually booted. Each version costs roughly 8.7 GB of snapshot storage.

The keep rule, per image definition:
  * every version referenced by a live VM or VMSS anywhere in the subscription
  * the newest N versions, for rollback
  * anything not fully published yet (a build may be mid-publish right now)

Every image definition in the gallery is pruned, discovered at run time rather
than listed here. lib_main_gallery is the only gallery in the subscription and
sibling repos build into it too - mccarthy-infra publishes mccarthy-rocky-linux-9
here - so a hard-coded list would silently let every project except lib-main grow
forever. A new site gets covered the day it first publishes, with no edit here.

Dry run by default. Pass --apply to actually delete.
"""

import argparse
import json
import subprocess
import sys
import time

GALLERY = "lib_main_gallery"
RESOURCE_GROUP = "lib-main-images-rg"

# How many recent versions to keep for rollback, beyond whatever is live.
DEFAULT_KEEP_NEWEST = 10
KEEP_NEWEST_OVERRIDES = {
    # Base images build ~1/month and app builds always use the newest, so a
    # deep history buys nothing. App definitions build ~14/month and keep the
    # default, which is a few weeks of rollback.
    "drupal-base-rocky-linux-9": 3,
}

# Escape hatch: definitions listed here are never touched at all. Empty on
# purpose - use it only to park a definition during an incident, not as the
# normal way to protect images. The live-VM and keep-newest rules are what
# protect images in normal operation.
NEVER_PRUNE = set()


def keep_newest_for(definition):
    return KEEP_NEWEST_OVERRIDES.get(definition, DEFAULT_KEEP_NEWEST)


def prunable_definitions():
    """Every image definition in the gallery, minus any parked in NEVER_PRUNE."""
    definitions = [
        d["name"] for d in az(
            "sig", "image-definition", "list",
            "--gallery-name", GALLERY,
            "-g", RESOURCE_GROUP,
        ) or []
    ]
    for definition in sorted(NEVER_PRUNE & set(definitions)):
        print(f"Skipping {definition} entirely (listed in NEVER_PRUNE).")
    return sorted(d for d in definitions if d not in NEVER_PRUNE)


def az(*args):
    """Run an az command and return parsed JSON."""
    result = subprocess.run(
        ["az", *args, "-o", "json"],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout or "null")


def images_in_use():
    """Every gallery image version id referenced by a live VM or VMSS."""
    in_use = set()

    for vmss in az("vmss", "list") or []:
        ref = (
            vmss.get("virtualMachineProfile", {})
            .get("storageProfile", {})
            .get("imageReference")
            or {}
        )
        if ref.get("id"):
            in_use.add(ref["id"].lower())

    for vm in az("vm", "list") or []:
        ref = vm.get("storageProfile", {}).get("imageReference") or {}
        if ref.get("id"):
            in_use.add(ref["id"].lower())

    return in_use


def plan_for(definition, keep_newest, in_use):
    """Split one definition's versions into (keep, delete), newest first."""
    versions = az(
        "sig", "image-version", "list",
        "--gallery-name", GALLERY,
        "-g", RESOURCE_GROUP,
        "--gallery-image-definition", definition,
    ) or []

    # Leave anything that is not fully published alone. A build publishing a
    # version right now shows up here as Creating, and a Creating version may
    # have no publishedDate yet - which would sort it to the BOTTOM of the
    # newest-first list below and make the build's own fresh image the first
    # thing we delete. Skipping non-Succeeded versions removes that race, which
    # matters because a base build has been observed running for 6 hours and any
    # merge to lib-main dev can publish an app version at any time of day.
    in_flight = [v for v in versions if v.get("provisioningState") != "Succeeded"]
    versions = [v for v in versions if v.get("provisioningState") == "Succeeded"]

    # Sort by publishedDate, not by name: name order is lexical, so 0.0.9 would
    # sort above 0.0.10 and the keep-newest window would hold the wrong versions.
    versions.sort(
        key=lambda v: v.get("publishingProfile", {}).get("publishedDate", ""),
        reverse=True,
    )

    keep, delete = [], []
    for index, version in enumerate(versions):
        live = version["id"].lower() in in_use
        recent = index < keep_newest
        reason = "live" if live else ("recent" if recent else None)
        (keep if reason else delete).append((version, reason))

    return keep, delete, in_flight


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="actually delete; without it this only prints what it would do",
    )
    parser.add_argument(
        "--timeout-minutes",
        type=int,
        default=45,
        help="how long to wait for the submitted deletes to finish",
    )
    args = parser.parse_args()

    in_use = images_in_use()
    print(f"Image versions in use by a live VM or VMSS: {len(in_use)}")
    for image_id in sorted(in_use):
        print(f"  live: {image_id}")
    if not in_use:
        # Every gallery version would look unused, so the keep-newest window is
        # the only thing standing between us and deleting a running image.
        sys.exit("Refusing to run: found no images in use at all, which almost "
                 "certainly means the az query failed rather than that nothing "
                 "is running.")

    submitted = {}

    for definition in prunable_definitions():
        keep, delete, in_flight = plan_for(
            definition, keep_newest_for(definition), in_use)
        print(f"\n=== {definition}: keeping {len(keep)}, deleting {len(delete)}"
              f"{f', skipping {len(in_flight)} in flight' if in_flight else ''} ===")
        for version in in_flight:
            print(f"  skip   {version['name']:<12} "
                  f"(provisioningState={version.get('provisioningState')} - a build is "
                  f"mid-publish or mid-delete, leave it alone)")
        for version, reason in keep:
            print(f"  keep   {version['name']:<12} ({reason})")

        for version, _ in delete:
            name = version["name"]
            if not args.apply:
                print(f"  DRYRUN would delete {name}")
                continue
            # --no-wait, because a single delete takes a couple of minutes and
            # doing 80 of them in series takes hours. Azure runs them in
            # parallel; wait_for_deletes() below confirms they finished.
            try:
                subprocess.run(
                    ["az", "sig", "image-version", "delete", "--no-wait",
                     "--gallery-name", GALLERY,
                     "-g", RESOURCE_GROUP,
                     "--gallery-image-definition", definition,
                     "--gallery-image-version", name],
                    check=True,
                )
                print(f"  submitted delete for {name}")
                submitted.setdefault(definition, set()).add(name)
            except subprocess.CalledProcessError:
                print(f"::warning::Could not submit delete for {definition} {name}")

    if not args.apply:
        print("\nDry run - nothing was deleted.")
        return 0

    return wait_for_deletes(submitted, args.timeout_minutes)


def wait_for_deletes(submitted, timeout_minutes):
    """Poll until every submitted version is gone, or we run out of patience."""
    deadline = time.monotonic() + timeout_minutes * 60
    remaining = {d: set(names) for d, names in submitted.items() if names}

    while remaining and time.monotonic() < deadline:
        time.sleep(30)
        for definition in list(remaining):
            live_names = {
                v["name"]
                for v in az("sig", "image-version", "list",
                            "--gallery-name", GALLERY,
                            "-g", RESOURCE_GROUP,
                            "--gallery-image-definition", definition) or []
            }
            remaining[definition] &= live_names
            if not remaining[definition]:
                del remaining[definition]
        still = sum(len(names) for names in remaining.values())
        print(f"  waiting on {still} delete(s)...")

    if remaining:
        for definition, names in remaining.items():
            print(f"::warning::{definition}: still present after "
                  f"{timeout_minutes}m: {', '.join(sorted(names))}")
        return 1

    total = sum(len(names) for names in submitted.values())
    print(f"\nDeleted {total} version(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
