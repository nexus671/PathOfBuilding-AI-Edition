"""Exercise native controls and audit rendered frames without opening a window."""
# cspell:ignore lupa
import argparse
from concurrent.futures import ProcessPoolExecutor
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

from render_headless_ui import render
from update_crafting_currency_art import check as check_currency_art
from update_colour_picker_art import check as check_colour_art
from update_map_item_art import check as check_map_item_art

ROOT = Path(__file__).resolve().parents[1]


def source_hashes():
    sources = list((ROOT / "src/Classes").glob("*.lua")) + list((ROOT / "src/Modules").glob("*.lua"))
    sources += list((ROOT / "src/Data").rglob("*.lua"))
    sources += list((ROOT / "src/AI").rglob("*.cjs"))
    sources += list((ROOT / "runtime/SimpleGraphic/Fonts").glob("*"))
    sources += list((ROOT / "runtime/lua").rglob("*.lua"))
    sources += list((ROOT / "src/Assets/Crafting").rglob("*"))
    sources += list((ROOT / "src/Assets/MapCrafting").rglob("*"))
    sources += list((ROOT / "src/Assets/Atlas").rglob("*"))
    sources += list((ROOT / "src/Data/Atlas").glob("*.json"))
    sources += list((ROOT / "src/Data/Genesis").glob("*.json"))
    sources += list((ROOT / "src/Assets/Genesis").rglob("*"))
    sources += list((ROOT / "src/Data/Crafting").glob("*.json"))
    sources += list((ROOT / "src/Data/LootFilters").rglob("*"))
    sources += [ROOT / "tools/update_harvest_enchants.py", ROOT / "tools/update_harvest_damage_330.py", ROOT / "tools/update_crafting_data.py", ROOT / "tools/crafting_data_status.py", ROOT / "tools/test_crafting_data_status.py", ROOT / "tools/update_modifier_overlay_330.py", ROOT / "tools/test_modifier_overlay_330.py", ROOT / "tools/update_allflame_data.py", ROOT / "tools/update_map_crafting_art.py", ROOT / "tools/check_map_crafting_art.py", ROOT / "tools/update_map_item_art.py", ROOT / "tools/update_map_variant_art.py", ROOT / "tools/test_update_map_variant_art.py"]
    sources += list((ROOT / "src/Data/LootFilters").glob("*"))
    sources += list((ROOT / "src/Assets/LootFilters").glob("*"))
    sources += list((ROOT / "src/TreeData/3_30").glob("*"))
    sources += list((ROOT / "src/TreeData/3_30_ruthless").glob("*"))
    sources += list((ROOT / "src/TreeData/3_30_preview").glob("*"))
    sources += [ROOT / "src/_SimpleGraphic.def.lua", ROOT / "src/GameVersions.lua", ROOT / "src/Data/HeadlessImageSizes.json", ROOT / "tools/update_loot_filter_base_metadata.py", ROOT / "tools/test_update_loot_filter_data.py"]
    sources += [ROOT / "src/HeadlessWrapper.lua", ROOT / "src/Data/Global.lua", Path(__file__), ROOT / "tools/render_headless_ui.py", ROOT / "tools/test_render_headless_ui.py", ROOT / "tools/test_headless_ui.lua", ROOT / "tools/test_unique_count_ui.lua", ROOT / "tools/test_unique_catalyst_ui.lua", ROOT / "tools/test_unique_omen_ui.lua", ROOT / "tools/test_unique_colour_ui.lua", ROOT / "tools/test_originator_ui.lua", ROOT / "tools/update_crafting_currency_art.py", ROOT / "tools/update_colour_picker_art.py", ROOT / "tools/update_loot_filter_base_classes.py"]
    sources.append(ROOT / "tools/test_tincture_hint.lua")
    sources.append(ROOT / "tools/test_combined_fossil_ui.lua")
    sources.append(ROOT / "tools/test_vendor_review_ui.lua")
    sources.append(ROOT / "tools/test_vendor_base_ui.lua")
    sources.append(ROOT / "tools/test_bounded_planning_errors.lua")
    sources.append(ROOT / "tools/test_modifier_paging_ui.lua")
    sources.append(ROOT / "tools/test_crafting_replay_ui.lua")
    sources.append(ROOT / "tools/test_crafting_sequence_ui.lua")
    sources.append(ROOT / "tools/test_dialla_socket_restriction.lua")
    sources.append(ROOT / "tools/test_unique_nonwhite_ui.lua")
    sources.append(ROOT / "tools/test_genesis_ui.lua")
    sources.append(ROOT / "tools/test_atlas_remove_ui.lua")
    sources.append(ROOT / "tools/test_atlas_search_ui.lua")
    sources.append(ROOT / "tools/test_atlas_preview_details_ui.lua")
    sources.append(ROOT / "tools/test_crafting_blank_ui.lua")
    sources.append(ROOT / "tools/test_crafting_base_implicit_ui.lua")
    sources.append(ROOT / "tools/test_unique_random_guide_ui.lua")
    sources.append(ROOT / "tools/test_unique_fractional_ui.lua")
    sources.append(ROOT / "tools/test_unique_variant_divine_ui.lua")
    sources.append(ROOT / "tools/test_filter_export_race.lua")
    sources.append(ROOT / "tools/test_filter_review_ui.lua")
    sources.append(ROOT / "tools/test_crafting_base_cost_ui.lua")
    sources.append(ROOT / "tools/test_unique_sacred_ui.lua")
    sources.append(ROOT / "tools/test_recipe_currency_help.lua")
    sources.append(ROOT / "tools/test_sacred_exact_ui.lua")
    sources.append(ROOT / "tools/test_filter_unique_review.lua")
    sources.append(ROOT / "tools/test_filter_sound_list_ui.lua")
    sources.append(ROOT / "tools/test_filter_contradictions.lua")
    sources.append(ROOT / "tools/test_craft_project_recovery.lua")
    sources.append(ROOT / "tools/test_bench_rarity_preview.lua")
    sources.append(ROOT / "tools/test_update_notes_ui.lua")
    sources.append(ROOT / "tools/test_fated_scene_ui.lua")
    sources.append(ROOT / "tools/test_filter_union_ui.lua")
    sources.append(ROOT / "tools/test_atlas_plan_pickups_ui.lua")
    sources.append(ROOT / "tools/test_quality_calculation_ui.lua")
    sources.append(ROOT / "tools/test_gem_quality_ui.lua")
    sources.append(ROOT / "tools/test_global_crafting_item_ui.lua")
    sources.append(ROOT / "tools/test_planning_bundle_errors.lua")
    sources.append(ROOT / "tools/test_beast_max_sockets.lua")
    sources.append(ROOT / "tools/test_beast_max_sockets_ui.lua")
    sources.append(ROOT / "tools/test_unique_beast_sockets.lua")
    sources.append(ROOT / "tools/test_anoint_sort_ui.lua")
    sources.append(ROOT / "tools/test_timeless_dialog_ui.lua")
    sources.append(ROOT / "tools/test_ai_filter_proposal_ui.lua")
    sources.append(ROOT / "tools/test_ai_filter_handoff.lua")
    sources.append(ROOT / "tools/test_ai_journey_proposal_ui.lua")
    sources.append(ROOT / "tools/test_ai_atlas_proposal_ui.lua")
    sources.append(ROOT / "tools/test_ai_crafting_proposal_ui.lua")
    sources.append(ROOT / "tools/test_crafting_guide_ui.lua")
    sources.append(ROOT / "tools/test_journey_crafting_guide_ui.lua")
    sources.append(ROOT / "tools/test_flask_enchant_ui.lua")
    sources.append(ROOT / "tools/test_unique_flask_enchant_ui.lua")
    sources.append(ROOT / "tools/test_map_vaal_ui.lua")
    sources.append(ROOT / "tools/test_minimal_ui.lua")
    sources += [ROOT / "tools/test_gwennen_ui.lua", ROOT / "tools/test_rog_ui.lua"]
    sources.append(ROOT / "tools/test_magic_name_ui.lua")
    sources += [ROOT / "tools/update_flask_enchant_data.py", ROOT / "tools/test_update_flask_enchant_data.py"]
    sources.append(ROOT / "tools/run_headless_lupa.py")
    sources.append(ROOT / "tools/test_campaign_selection_ui.lua")
    sources += [ROOT / "manifest.xml", ROOT / "changelog.txt"]
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(sources) if path.is_file()}


def render_frame(path):
    image, audit = render(json.loads(path.read_text()))
    image.save(path.parent.parent / (path.stem + ".png"))
    (path.parent.parent / (path.stem + ".audit.json")).write_text(json.dumps(audit, indent=2))
    if any(audit[key] for key in ("lowContrast", "horizontalClipping", "controlClipping", "controlOverlaps", "hiddenText")):
        return {"frame": path.name, "audit": audit}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", default="luajit", help="LuaJIT executable; defaults to PATH")
    parser.add_argument("--lupa", action="store_true", help="Use Python Lupa with the headless filesystem adapter")
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/headless-ui")
    parser.add_argument("--workers", type=int, default=min(4, os.cpu_count() or 1), help="Parallel render processes (1 to 4)")
    args = parser.parse_args()
    assert 1 <= args.workers <= 4, "Use 1 to 4 render workers"
    check_currency_art()
    check_colour_art()
    check_map_item_art()
    from update_map_variant_art import check as check_map_variant_art
    check_map_variant_art()
    hashes = source_hashes()
    args.output.mkdir(parents=True, exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix="run-", dir=args.output.resolve()))
    frames = directory / "frames"
    frames.mkdir()
    environment = dict(os.environ, LUA_PATH="../runtime/lua/?.lua;../runtime/lua/?/init.lua;;")
    if os.name == "nt":
        environment["LUA_CPATH"] = str(ROOT / "runtime/?.dll") + ";;"
        environment["PATH"] = str(ROOT / "runtime") + os.pathsep + environment["PATH"]
    lua_command = [sys.executable, str(ROOT / "tools/run_headless_lupa.py"), "--filesystem"] if args.lupa else [args.lua]
    result = subprocess.run(lua_command + ["../tools/test_headless_ui.lua", str(frames)], cwd=ROOT / "src",
                            env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "controls.log").write_text(result.stdout)
    assert result.returncode == 0, result.stdout
    filter_contradictions = subprocess.run(lua_command + ["../tools/test_filter_contradictions.lua", str(frames)], cwd=ROOT / "src",
                                          env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "filter-contradictions-controls.log").write_text(filter_contradictions.stdout)
    assert filter_contradictions.returncode == 0, filter_contradictions.stdout
    craft_recovery = subprocess.run(lua_command + ["../tools/test_craft_project_recovery.lua"], cwd=ROOT / "src",
                                    env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "craft-project-recovery.log").write_text(craft_recovery.stdout)
    assert craft_recovery.returncode == 0, craft_recovery.stdout
    bench_rarity = subprocess.run(lua_command + ["../tools/test_bench_rarity_preview.lua", str(frames)], cwd=ROOT / "src",
                                  env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "bench-rarity-preview.log").write_text(bench_rarity.stdout)
    assert bench_rarity.returncode == 0, bench_rarity.stdout
    update_notes = subprocess.run(lua_command + ["../tools/test_update_notes_ui.lua", str(frames)], cwd=ROOT / "src",
                                  env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "update-notes-controls.log").write_text(update_notes.stdout)
    assert update_notes.returncode == 0, update_notes.stdout
    atlas_search = subprocess.run(lua_command + ["../tools/test_atlas_search_ui.lua", str(frames)], cwd=ROOT / "src",
                                  env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "atlas-search-controls.log").write_text(atlas_search.stdout)
    assert atlas_search.returncode == 0, atlas_search.stdout
    atlas_preview = subprocess.run(lua_command + ["../tools/test_atlas_preview_details_ui.lua"], cwd=ROOT / "src",
                                   env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "atlas-preview-details-controls.log").write_text(atlas_preview.stdout)
    assert atlas_preview.returncode == 0, atlas_preview.stdout
    filter_unique = subprocess.run(lua_command + ["../tools/test_filter_unique_review.lua"], cwd=ROOT / "src",
                                   env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "filter-unique-review.log").write_text(filter_unique.stdout)
    assert filter_unique.returncode == 0, filter_unique.stdout
    atlas_removal = subprocess.run(lua_command + ["../tools/test_atlas_remove_ui.lua"], cwd=ROOT / "src",
                                   env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "atlas-removal-controls.log").write_text(atlas_removal.stdout)
    assert atlas_removal.returncode == 0, atlas_removal.stdout
    blank_base = subprocess.run(lua_command + ["../tools/test_crafting_blank_ui.lua"], cwd=ROOT / "src",
                                env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "crafting-blank-base-controls.log").write_text(blank_base.stdout)
    assert blank_base.returncode == 0, blank_base.stdout
    base_implicit = subprocess.run(lua_command + ["../tools/test_crafting_base_implicit_ui.lua"], cwd=ROOT / "src",
                                   env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "crafting-base-implicit-controls.log").write_text(base_implicit.stdout)
    assert base_implicit.returncode == 0, base_implicit.stdout
    unique_random_guide = subprocess.run(lua_command + ["../tools/test_unique_random_guide_ui.lua"], cwd=ROOT / "src",
                                         env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "unique-random-guide-controls.log").write_text(unique_random_guide.stdout)
    assert unique_random_guide.returncode == 0, unique_random_guide.stdout
    unique_fractional = subprocess.run(lua_command + ["../tools/test_unique_fractional_ui.lua"], cwd=ROOT / "src",
                                       env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "unique-fractional-controls.log").write_text(unique_fractional.stdout)
    assert unique_fractional.returncode == 0, unique_fractional.stdout
    unique_variant_divine = subprocess.run(lua_command + ["../tools/test_unique_variant_divine_ui.lua"], cwd=ROOT / "src",
                                           env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "unique-variant-divine-controls.log").write_text(unique_variant_divine.stdout)
    assert unique_variant_divine.returncode == 0, unique_variant_divine.stdout
    filter_race = subprocess.run(lua_command + ["../tools/test_filter_export_race.lua"], cwd=ROOT / "src",
                                 env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "filter-export-race-controls.log").write_text(filter_race.stdout)
    assert filter_race.returncode == 0, filter_race.stdout
    filter_review = subprocess.run(lua_command + ["../tools/test_filter_review_ui.lua"], cwd=ROOT / "src",
                                   env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "filter-review-controls.log").write_text(filter_review.stdout)
    assert filter_review.returncode == 0, filter_review.stdout
    base_cost = subprocess.run(lua_command + ["../tools/test_crafting_base_cost_ui.lua"], cwd=ROOT / "src",
                               env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "crafting-base-cost-controls.log").write_text(base_cost.stdout)
    assert base_cost.returncode == 0, base_cost.stdout
    sacred = subprocess.run(lua_command + ["../tools/test_unique_sacred_ui.lua", str(frames)], cwd=ROOT / "src",
                            env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "unique-sacred-controls.log").write_text(sacred.stdout)
    assert sacred.returncode == 0, sacred.stdout
    recipe_help = subprocess.run(lua_command + ["../tools/test_recipe_currency_help.lua"], cwd=ROOT / "src",
                                 env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "recipe-currency-help-controls.log").write_text(recipe_help.stdout)
    assert recipe_help.returncode == 0, recipe_help.stdout
    sacred_exact = subprocess.run(lua_command + ["../tools/test_sacred_exact_ui.lua"], cwd=ROOT / "src",
                                  env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "sacred-exact-controls.log").write_text(sacred_exact.stdout)
    assert sacred_exact.returncode == 0, sacred_exact.stdout
    filter_sound_list = subprocess.run(lua_command + ["../tools/test_filter_sound_list_ui.lua", str(frames)], cwd=ROOT / "src",
                                       env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "filter-sound-list-controls.log").write_text(filter_sound_list.stdout)
    assert filter_sound_list.returncode == 0, filter_sound_list.stdout
    fated_scene = subprocess.run(lua_command + ["../tools/test_fated_scene_ui.lua"], cwd=ROOT / "src",
                                 env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "fated-scene-controls.log").write_text(fated_scene.stdout)
    assert fated_scene.returncode == 0, fated_scene.stdout
    filter_union = subprocess.run(lua_command + ["../tools/test_filter_union_ui.lua"], cwd=ROOT / "src",
                                  env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "filter-union-controls.log").write_text(filter_union.stdout)
    assert filter_union.returncode == 0, filter_union.stdout
    atlas_pickups = subprocess.run(lua_command + ["../tools/test_atlas_plan_pickups_ui.lua"], cwd=ROOT / "src",
                                   env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "atlas-plan-pickups-controls.log").write_text(atlas_pickups.stdout)
    assert atlas_pickups.returncode == 0, atlas_pickups.stdout
    quality_calculation = subprocess.run(lua_command + ["../tools/test_quality_calculation_ui.lua"], cwd=ROOT / "src",
                                         env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "quality-calculation-controls.log").write_text(quality_calculation.stdout)
    assert quality_calculation.returncode == 0, quality_calculation.stdout
    gem_quality = subprocess.run(lua_command + ["../tools/test_gem_quality_ui.lua"], cwd=ROOT / "src",
                                 env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "gem-quality-controls.log").write_text(gem_quality.stdout)
    assert gem_quality.returncode == 0, gem_quality.stdout
    global_crafting_item = subprocess.run(lua_command + ["../tools/test_global_crafting_item_ui.lua", str(frames)], cwd=ROOT / "src",
                                          env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "global-crafting-item-controls.log").write_text(global_crafting_item.stdout)
    assert global_crafting_item.returncode == 0, global_crafting_item.stdout
    bundle_errors = subprocess.run(lua_command + ["../tools/test_planning_bundle_errors.lua", str(frames)], cwd=ROOT / "src",
                                   env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "planning-bundle-errors.log").write_text(bundle_errors.stdout)
    assert bundle_errors.returncode == 0, bundle_errors.stdout
    for script in ("test_beast_max_sockets.lua", "test_beast_max_sockets_ui.lua"):
        arguments = lua_command + ["../tools/" + script]
        if script.endswith("_ui.lua"):
            arguments.append(str(frames))
        check = subprocess.run(arguments, cwd=ROOT / "src", env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        (directory / (script + ".log")).write_text(check.stdout)
        assert check.returncode == 0, check.stdout
    unique_beast = subprocess.run(lua_command + ["../tools/test_unique_beast_sockets.lua", str(frames)], cwd=ROOT / "src",
                                  env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "unique-beast-sockets.log").write_text(unique_beast.stdout)
    assert unique_beast.returncode == 0, unique_beast.stdout
    anoint_sort = subprocess.run(lua_command + ["../tools/test_anoint_sort_ui.lua"], cwd=ROOT / "src",
                                 env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "anoint-sort-controls.log").write_text(anoint_sort.stdout)
    assert anoint_sort.returncode == 0, anoint_sort.stdout
    timeless_dialog = subprocess.run(lua_command + ["../tools/test_timeless_dialog_ui.lua"], cwd=ROOT / "src",
                                     env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "timeless-dialog-controls.log").write_text(timeless_dialog.stdout)
    assert timeless_dialog.returncode == 0, timeless_dialog.stdout
    vendor_base = subprocess.run(lua_command + ["../tools/test_vendor_base_ui.lua"], cwd=ROOT / "src",
                                 env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "vendor-base-controls.log").write_text(vendor_base.stdout)
    assert vendor_base.returncode == 0, vendor_base.stdout
    ai_filter_review = subprocess.run(lua_command + ["../tools/test_ai_filter_proposal_ui.lua"], cwd=ROOT / "src",
                                      env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "ai-filter-review-controls.log").write_text(ai_filter_review.stdout)
    assert ai_filter_review.returncode == 0, ai_filter_review.stdout
    ai_filter_handoff = subprocess.run(lua_command + ["../tools/test_ai_filter_handoff.lua"], cwd=ROOT / "src",
                                       env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "ai-filter-handoff-controls.log").write_text(ai_filter_handoff.stdout)
    assert ai_filter_handoff.returncode == 0, ai_filter_handoff.stdout
    ai_journey_review = subprocess.run(lua_command + ["../tools/test_ai_journey_proposal_ui.lua"], cwd=ROOT / "src",
                                       env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "ai-journey-review-controls.log").write_text(ai_journey_review.stdout)
    assert ai_journey_review.returncode == 0, ai_journey_review.stdout
    ai_atlas_review = subprocess.run(lua_command + ["../tools/test_ai_atlas_proposal_ui.lua"], cwd=ROOT / "src",
                                     env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "ai-atlas-review-controls.log").write_text(ai_atlas_review.stdout)
    assert ai_atlas_review.returncode == 0, ai_atlas_review.stdout
    ai_crafting_review = subprocess.run(lua_command + ["../tools/test_ai_crafting_proposal_ui.lua"], cwd=ROOT / "src",
                                        env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "ai-crafting-review-controls.log").write_text(ai_crafting_review.stdout)
    assert ai_crafting_review.returncode == 0, ai_crafting_review.stdout
    bounded_errors = subprocess.run(lua_command + ["../tools/test_bounded_planning_errors.lua"], cwd=ROOT / "src",
                                    env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "bounded-planning-errors.log").write_text(bounded_errors.stdout)
    assert bounded_errors.returncode == 0, bounded_errors.stdout
    replay = subprocess.run(lua_command + ["../tools/test_crafting_replay_ui.lua", str(frames)], cwd=ROOT / "src",
                            env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "crafting-replay-controls.log").write_text(replay.stdout)
    assert replay.returncode == 0, replay.stdout
    sequence = subprocess.run(lua_command + ["../tools/test_crafting_sequence_ui.lua"], cwd=ROOT / "src",
                              env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "crafting-sequence-controls.log").write_text(sequence.stdout)
    assert sequence.returncode == 0, sequence.stdout
    dialla = subprocess.run(lua_command + ["../tools/test_dialla_socket_restriction.lua"], cwd=ROOT / "src",
                            env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "dialla-socket-restriction.log").write_text(dialla.stdout)
    assert dialla.returncode == 0, dialla.stdout
    unique_nonwhite = subprocess.run(lua_command + ["../tools/test_unique_nonwhite_ui.lua"], cwd=ROOT / "src",
                                     env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "unique-nonwhite-controls.log").write_text(unique_nonwhite.stdout)
    assert unique_nonwhite.returncode == 0, unique_nonwhite.stdout
    genesis = subprocess.run(lua_command + ["../tools/test_genesis_ui.lua", str(frames)], cwd=ROOT / "src",
                             env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "genesis-controls.log").write_text(genesis.stdout)
    assert genesis.returncode == 0, genesis.stdout
    guide = subprocess.run(lua_command + ["../tools/test_crafting_guide_ui.lua", str(frames)], cwd=ROOT / "src",
                           env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "crafting-guide-controls.log").write_text(guide.stdout)
    assert guide.returncode == 0, guide.stdout
    journey_guide = subprocess.run(lua_command + ["../tools/test_journey_crafting_guide_ui.lua", str(frames)], cwd=ROOT / "src",
                                   env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "journey-crafting-guide-controls.log").write_text(journey_guide.stdout)
    assert journey_guide.returncode == 0, journey_guide.stdout
    flask_enchants = subprocess.run(lua_command + ["../tools/test_flask_enchant_ui.lua", str(frames)], cwd=ROOT / "src",
                                    env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "flask-enchant-controls.log").write_text(flask_enchants.stdout)
    assert flask_enchants.returncode == 0, flask_enchants.stdout
    unique_flask = subprocess.run(lua_command + ["../tools/test_unique_flask_enchant_ui.lua", str(frames)], cwd=ROOT / "src",
                                  env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "unique-flask-enchant-controls.log").write_text(unique_flask.stdout)
    assert unique_flask.returncode == 0, unique_flask.stdout
    map_vaal = subprocess.run(lua_command + ["../tools/test_map_vaal_ui.lua", str(frames)], cwd=ROOT / "src",
                              env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "map-vaal-controls.log").write_text(map_vaal.stdout)
    assert map_vaal.returncode == 0, map_vaal.stdout
    assert source_hashes() == hashes, "Source files changed during UI capture; repeat against stable sources"
    for width in (1280, 1024, 960):
        archive = frames / f"ui-{width}-strictnesses.zip"
        with zipfile.ZipFile(archive) as z:
            assert z.namelist() == [f"ui-{width}-{n}.filter" for n in range(7)], "ZIP has incorrect strictness files"
            assert z.testzip() is None, "ZIP failed CRC validation"
            assert all(b"Covens pickup plan" in z.read(name) for name in z.namelist()), "ZIP lost the personal filter"
        archive.unlink()
        ruthless_archive = frames / f"ruthless-{width}-strictnesses.zip"
        with zipfile.ZipFile(ruthless_archive) as z:
            assert z.namelist() == [f"ruthless-{width}-{n}.ruthlessfilter" for n in range(7)], "Ruthless ZIP has incorrect filenames"
            assert z.testzip() is None, "Ruthless ZIP failed CRC validation"
            assert all(b"Minimal" in z.read(name) for name in z.namelist()), "Ruthless ZIP lost its mode-specific rules"
        ruthless_archive.unlink()
    paths = sorted(frames.glob("*.json"))
    assert len(paths) == 2429, f"Expected 2429 UI frames, found {len(paths)}"
    for name in ("960-inventory-source.json", "960-inventory-source-detail.json"):
        assert (frames / name).is_file(), f"Missing saved-item source view: {name}"
    for width in (960, 1024, 1280):
        assert (frames / f"{width}-unique-beast-sockets.json").is_file(), f"Missing unique Bestiary socket view at {width}px"
        assert (frames / f"{width}-beast-max-sockets.json").is_file(), f"Missing Bestiary socket view at {width}px"
        assert (frames / f"{width}-planning-bundle-error.json").is_file(), f"Missing planning-bundle error at {width}px"
        for view in ("list", "manager", "result", "failure"):
            assert (frames / f"{width}-filter-sound-{view}.json").is_file(), f"Missing sound {view} at {width}px"
        for view in ("search", "selected"):
            assert (frames / f"{width}-global-crafting-item-{view}.json").is_file(), f"Missing global item {view} at {width}px"
        for scene in ("beyond", "incursion"):
            assert (frames / f"{width}-filter-{scene}-examples.json").is_file(), f"Missing {scene} scene at {width}px"
        def label_and_background(name):
            commands = json.loads((frames / f"{width}-{name}.json").read_text())["commands"]
            index = next(i for i in range(len(commands) - 1, -1, -1) if commands[i].get("kind") == "text" and commands[i].get("text") == "Iron Hat")
            return commands[index], commands[index - 1]
        minimal_label, minimal_background = label_and_background("filter-minimal-default")
        shown_label, shown_background = label_and_background("filter-minimal-show")
        assert minimal_label["fontHeight"] < shown_label["fontHeight"] and minimal_background["color"][3] == 0 and shown_background["color"][3] > 0, "Minimal preview did not use its small transparent defaults"
        replay_frame = json.loads((frames / f"{width}-saved-replay.json").read_text())
        replay_text = " ".join(c.get("text", "") for c in replay_frame["commands"] if c.get("kind") == "text")
        assert "Rerun saved" in replay_text and "Saved simulation setup available" in replay_text, "Saved simulation is not discoverable"
        steps_frame = json.loads((frames / f"{width}-crafting-step-spending.json").read_text())
        steps_text = " ".join(c.get("text", "") for c in steps_frame["commands"] if c.get("kind") == "text")
        assert "Step 1" in steps_text and "2.00 chaos" in steps_text, "Crafting step spending is not visible"
        audit = json.loads((frames / f"{width}-filter-error-audit.json").read_text())
        audit_text = " ".join(c.get("text", "") for c in audit["commands"] if c.get("kind") == "text")
        assert "AlwaysShow" in audit_text and ("PoE 2" in audit_text or "Path of Exile 2" in audit_text), "Filter audit does not show the selected error"
        vendor = json.loads((frames / f"{width}-filter-vendor-examples.json").read_text())
        vendor_text = " ".join(c.get("text", "") for c in vendor["commands"] if c.get("kind") == "text")
        assert all(label in vendor_text for label in ("6 sockets", "6 linked", "Quality gem", "Rare piece")), "Vendor examples lack their identifying labels"
        atlas_totals = json.loads((frames / f"{width}-atlas-added-modifiers.json").read_text())
        assert any("increased effect of Explicit" in c.get("text", "") for c in atlas_totals["commands"]), "Atlas modifier summary is missing"
        atlas_comparison = json.loads((frames / f"{width}-atlas-modifier-comparison.json").read_text())
        assert any("Change: +" in c.get("text", "") for c in atlas_comparison["commands"]), "Atlas modifier comparison is not visible"
        catalyst = json.loads((frames / f"{width}-crafting-unique-ring-catalyst.json").read_text())
        catalyst_text = " ".join(c.get("text", "") for c in catalyst["commands"] if c.get("kind") == "text")
        assert "Prismatic catalyst: +20%" in catalyst_text and "Catalyst quality: 20%" in catalyst_text, "Catalyst card and status disagree"
        before = json.loads((frames / f"{width}-crafting-unique-quality.json").read_text())
        count_menu = json.loads((frames / f"{width}-crafting-unique-count-menu.json").read_text())
        assert any("10 Jeweller's Orbs + 10 Vaal Orbs" in c.get("text", "") for c in count_menu["commands"]), "Corrupted socket-count cost is missing"
        count_result = json.loads((frames / f"{width}-crafting-unique-count-result.json").read_text())
        assert any("Sockets: R-G B W" in c.get("text", "") for c in count_result["commands"]), "Unique socket-count preview is missing"
        unique_art = {c.get("asset") for c in before["commands"]}
        assert {"Assets/Crafting/Currency/f3bee36504af7453ea82.png", "Assets/Crafting/Currency/93c6d800e09f89a9a227.png", "Assets/Crafting/Currency/141b8801937fdb05c570.png"} <= unique_art, "Unique crafting actions are missing their currency art"
        assert any("Quality: +0%" in c.get("text", "") for c in before["commands"]), "Unique item card does not show its quality"
        linked = json.loads((frames / f"{width}-crafting-unique-linked.json").read_text())
        recipe = json.loads((frames / f"{width}-crafting-unique-recipe-result.json").read_text())
        save_recipe = json.loads((frames / f"{width}-crafting-unique-save-recipe.json").read_text())
        assert any("Save recipe" in c.get("text", "") for c in save_recipe["commands"]), "Unique preview has no visible save recipe action"
        recipe_text = " ".join(c.get("text", "") for c in recipe["commands"] if c.get("kind") == "text")
        assert "Goal reached" in recipe_text and "Sockets: R-G-B" in recipe_text and "Keep as target" in recipe_text, "Unique recipe result is missing its outcome, item or target action"
        assert any("Sockets: R-G B" in c.get("text", "") for c in before["commands"]), "Starting socket layout is missing"
        assert any("Sockets: R-G-B" in c.get("text", "") for c in linked["commands"]), "Linked socket layout is missing"
        for name in ("crafting-unique-white-sockets", "crafting-unique-corrupted-white"):
            white = json.loads((frames / f"{width}-{name}.json").read_text())
            assert any("Sockets: W-W W" in c.get("text", "") for c in white["commands"]), "White socket preview is missing"
            assert any("1 Orb of Scouring" in c.get("text", "") for c in white["commands"]), "White socket cost is missing"
            if name == "crafting-unique-corrupted-white":
                assert any("1 Vaal Orb" in c.get("text", "") for c in white["commands"]), "Corrupted socket cost is missing"
        def socket_links(frame):
            title = next(c for c in frame["commands"] if c.get("kind") == "text" and c.get("text") == "WORKING ITEM")
            return [c for c in frame["commands"] if c.get("kind") == "rect" and c.get("width") == 7 and c.get("height") == 3
                    and c.get("y") == title["y"] + 124 and c.get("x", 0) > title["x"]]
        assert len(socket_links(before)) == 1 and len(socket_links(linked)) == 2, "Socket connectors did not reflect the link action"
        guide_review = json.loads((frames / f"{width}-crafting-unique-guide-review.json").read_text())
        guide_text = [c.get("text", "") for c in guide_review["commands"] if c.get("kind") == "text"]
        assert any("Acquire the unique helmet" in text for text in guide_text), "Guide review does not show the edited step"
        assert any("Confirm guide" in text for text in guide_text), "Guide review has no confirmation action"
        frame = json.loads((frames / f"{width}-crafting-rog-offer.json").read_text())
        currency_art = json.loads((ROOT / "src/Assets/Crafting/currencies.json").read_text())
        order_paths = {currency_art["items"][f"Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_{i}"]["path"] for i in range(1, 5)}
        assert order_paths <= {c.get("asset") for c in frame["commands"]}, "Rog offer is missing Order Artifact artwork"
        for name in ("crafting-rog-fill", "crafting-recipe-rog-fill"):
            frame = json.loads((frames / f"{width}-{name}.json").read_text())
            labels = " ".join(c.get("text", "") for c in frame["commands"] if c.get("kind") == "text")
            assert "Fill empty modifier slots" in labels and "estimated modifier weights" in labels, "Rog fill offer or model explanation is missing"
        frame = json.loads((frames / f"{width}-crafting-rog-socket-offer.json").read_text())
        labels = " ".join(c.get("text", "") for c in frame["commands"] if c.get("kind") == "text")
        assert "Observed rerolls" in labels and "estimated socket odds" in labels, "Rog socket offer explanation is missing"
        frame = json.loads((frames / f"{width}-crafting-rog-values-offer.json").read_text())
        labels = " ".join(c.get("text", "") for c in frame["commands"] if c.get("kind") == "text")
        assert "Reroll values of one modifier" in labels and "may not match your preference" in labels, "Rog value-offer note is missing"
        frame = json.loads((frames / f"{width}-crafting-recipe-rog-edit.json").read_text())
        labels = " ".join(c.get("text", "") for c in frame["commands"] if c.get("kind") == "text")
        assert "Add a modifier to one side" in labels and "Suffix" in labels, "Edited Rog offer is not visible"
        frame = json.loads((frames / f"{width}-crafting-recipe-rog-quality.json").read_text())
        labels = " ".join(c.get("text", "") for c in frame["commands"] if c.get("kind") == "text")
        assert "Set quality to 20%" in labels and "offer eligibility is unverified" in labels, "Rog quality offer or eligibility note is missing"
        frame = json.loads((frames / f"{width}-map-clipboard-imported.json").read_text())
        assert any(c.get("asset") == "Assets/MapCrafting/Items/MapTier5.png" for c in frame["commands"]), "Current map item artwork is missing"
        quality = next(c for c in frame["commands"] if c["kind"] == "text" and "Quality (Pack Size): +20%" in c.get("text", ""))
        card = next(c for c in frame["commands"] if c["kind"] == "rect" and c.get("color") == [0.082352941176471, 0.07843137254902, 0.10196078431373, 1])
        assert (quality["layer"], quality["sublayer"]) > (card["layer"], card["sublayer"]), "Map card obscures quality and modifier details"
        blighted = json.loads((frames / f"{width}-map-blighted-imported.json").read_text())
        assert any(c.get("asset") == "Assets/MapCrafting/Items/BlightedTier16.png" for c in blighted["commands"]), "Blighted map artwork is missing"
        ravaged = json.loads((frames / f"{width}-map-ravaged-imported.json").read_text())
        assert any("Blight-ravaged:" in c.get("text", "") for c in ravaged["commands"] if c.get("kind") == "text"), "Blight-ravaged map identity is not visible"
        assert any(c.get("asset") == "Assets/MapCrafting/Items/RavagedTier16.png" for c in ravaged["commands"]), "Blight-ravaged map artwork is missing"
        nightmare = json.loads((frames / f"{width}-map-nightmare-inspection.json").read_text())
        images = [c.get("asset") for c in nightmare["commands"]]
        background = images.index("Assets/MapCrafting/Items/NightmareFrame.png")
        symbol = images.index("Assets/MapCrafting/Items/9b88dbe87af6dda1c4ce.png")
        assert background < symbol, "Nightmare map frame must be drawn beneath its symbol"
    for width in (960, 1024, 1280):
        stack = json.loads((frames / f"{width}-filter-stack-styles.json").read_text())
        labels = " ".join(command.get("text", "") for command in stack["commands"] if command.get("kind") == "text")
        assert "Tier preview" in labels and "Example stack" in labels, "Stack style preview is missing"
        welcome = json.loads((frames / f"{width}-crafting-empty-workspace.json").read_text())
        labels = " ".join(command.get("text", "") for command in welcome["commands"] if command.get("kind") == "text")
        assert "Plan your next item" in labels and "Start a project" in labels, "Crafting welcome action is missing"
        unknown = json.loads((frames / f"{width}-crafting-unknown-sockets.json").read_text())
        labels = " ".join(command.get("text", "") for command in unknown["commands"] if command.get("kind") == "text")
        assert "Sockets unknown" in labels, "Unknown socket layout is not visible"
        quality = json.loads((frames / f"{width}-crafting-blessed-quality.json").read_text())
        labels = " ".join(command.get("text", "") for command in quality["commands"] if command.get("kind") == "text")
        assert "Fertile quality: +20%" in labels, "Catalyst quality is missing from the item card"
    for width in (960, 1024, 1280):
        chart = json.loads((frames / f"{width}-crafting-executed-chart.json").read_text())
        labels = " ".join(command.get("text", "") for command in chart["commands"] if command.get("kind") == "text")
        assert "executed actions" in labels.lower(), "Executed-action chart label is missing"
        polygons = [command for command in chart["commands"] if command.get("kind") == "polygon"]
        def is_color(command, rgb):
            return all(abs(component * 255 - expected) < 0.01 for component, expected in zip(command["color"], rgb))
        marker = next(index for index, command in enumerate(polygons) if is_color(command, (213, 222, 232)))
        curve = next(index for index, command in enumerate(polygons) if is_color(command, (121, 216, 160)))
        assert marker < curve, "Selection marker hides the crafting chart curve"
    for width in (960, 1024, 1280):
        route = json.loads((frames / f"{width}-atlas-impossible-start.json").read_text())
        warning = next(command for command in route["commands"] if "Starting plan cannot be reached" in command.get("text", ""))
        assert warning["y"] + warning["height"] <= warning["clip"][1] + warning["clip"][3], "Atlas starting-budget warning is clipped"
    for width in (960, 1024, 1280):
        sample = json.loads((frames / f"{width}-filter-tier-unknown.json").read_text())
        labels = " ".join(command.get("text", "") for command in sample["commands"] if command.get("kind") == "text")
        assert "Unidentified item tier: unknown" in labels, "The unknown drop tier is not visible"
        tier = next(command for command in sample["commands"] if "Unidentified item tier: unknown" in command.get("text", ""))
        assert tier["y"] + tier["height"] <= tier["clip"][1] + tier["clip"][3], "The unknown tier is clipped"
    for width in (960, 1024, 1280):
        odds = json.loads((frames / f"{width}-crafting-harvest-damage-odds.json").read_text())
        labels = " ".join(command.get("text", "") for command in odds["commands"] if command.get("kind") == "text")
        assert "assumed tiers" in labels and "Cold Damage to Attacks" in labels, "Modeled damage outcome or assumptions are not visible"
    for width in (960, 1024, 1280):
        jewel = json.loads((frames / f"{width}-crafting-assembled-eye-crafted.json").read_text())
        assert not any(command.get("kind") == "text" and command.get("text", "").startswith("Quality:") for command in jewel["commands"]), "Jewel card shows an inapplicable zero-quality stat"
    for width in (960, 1024, 1280):
        etched = json.loads((frames / f"{width}-crafting-etched-socket-options.json").read_text())
        labels = [command.get("text", "") for command in etched["commands"] if command.get("kind") == "text"]
        assert any("-1 to maximum Sockets" in label for label in labels), "Etched socket enchantment is missing"
        assert not any("maximum Sockets (Not supported" in label for label in labels), "Native socket reduction is not parsed"
    flask_asset = json.loads((ROOT / "src/Assets/Crafting/items.json").read_text())["bases"]["Small Life Flask"]["path"]
    for width in (960, 1024, 1280):
        for name in ("crafting-flask-vaal-ready", "crafting-flask-inventory", "journey-flask-card"):
            flask = json.loads((frames / f"{width}-{name}.json").read_text())
            layers = [command for command in flask["commands"] if command.get("asset") == flask_asset]
            assert layers and len(layers) % 2 == 0, f"Flask sprite layers missing in {name}"
            for index in range(0, len(layers), 2):
                pair = layers[index:index+2]
                assert all(len(layer.get("uv", [])) == 4 and all(abs(a-b) < 1e-9 for a, b in zip(layer["uv"], expected)) for layer, expected in zip(pair, ([2/3, 0, 1, 1], [0, 0, 1/3, 1]))), f"Flask sprite layers were not composed in {name}"
                assert all(pair[0][key] == pair[1][key] for key in ("x", "y", "width", "height")), f"Flask sprite layers do not align in {name}"
    for width in (960, 1024, 1280):
        frame = json.loads((frames / f"{width}-filter-background-default-alpha.json").read_text())
        expected = (10 / 255, 20 / 255, 30 / 255, 240 / 255)
        assert any(command.get("kind") == "rect" and all(abs(a-b) < 1e-6 for a, b in zip(command.get("color", ()), expected)) and len(command.get("color", ())) == 4 for command in frame["commands"]), "Background preview lost the game-default opacity"
    # Tree captures can take much longer than small dialogs. Start the largest
    # captures first so one tree does not hold the entire audit open at the end.
    scheduled = sorted(paths, key=lambda path: (-path.stat().st_size, path.name))
    render_start = time.perf_counter()
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        failures = [failure for failure in pool.map(render_frame, scheduled) if failure]
    render_seconds = time.perf_counter() - render_start
    tooltip = json.loads((directory / "expected-audit-tooltip.json").read_text())
    assert any(c["kind"] == "text" and c["sublayer"] == 100 and "Alt+3" in c["text"] for c in tooltip["commands"]), "Native tooltip fixture did not draw its overlay"
    image, audit = render(tooltip)
    image.save(directory / "expected-audit-tooltip.png")
    assert not any(audit[key] for key in ("lowContrast", "horizontalClipping", "controlClipping", "controlOverlaps", "hiddenText")), "Native tooltip was incorrectly treated as control content"
    negative = json.loads((directory / "expected-audit-failures.json").read_text())
    image, audit = render(negative)
    image.save(directory / "expected-audit-failures.png")
    assert audit["lowContrast"] and audit["horizontalClipping"] and audit["controlClipping"] and audit["controlOverlaps"], "UI audits failed to detect the deliberate bad fixture"
    assert "Overlay outside the viewport" in audit["horizontalClipping"], "Overlay text escaped the viewport audit"
    try:
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip()
        dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True, stderr=subprocess.DEVNULL).splitlines()
    except (FileNotFoundError, subprocess.CalledProcessError):
        revision = environment.get("GITHUB_SHA")
        dirty = None
    assert source_hashes() == hashes, "Source files changed during UI rendering; repeat against stable sources"
    (directory / "report.json").write_text(json.dumps({"revision": revision, "workingTreeChanges": dirty,
        "sourceHashes": hashes, "sourceStable": True, "frames": len(paths), "renderSeconds": round(render_seconds, 3), "failures": failures, "auditSelfTest": "passed",
        "limitations": negative["limitations"]}, indent=2))
    print(f"Headless UI: {len(paths)} frames, {len(failures)} failures. Artifacts: {directory}")
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
