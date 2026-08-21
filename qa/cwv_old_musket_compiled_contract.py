#!/usr/bin/env python3
"""Verify issue #1155's Old Musket in the compiled CWV root bundle.

The VT2 v189 unit-prefix and terminal material-table readers are the minimal
dependency-free subset proven by Doomrocket's
``tools/tests/test_warlock_weapon_pipeline.py``.  Keeping the parser here makes
the assertion independent of Blender and the proprietary game bundle tools.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path


MASK = (1 << 64) - 1
VT2_FORMAT = 0xF0000005
VT2X_FORMAT = 0xF0000006
SUPPORTED_FORMATS = (VT2_FORMAT, VT2X_FORMAT)
BLOCK_RAW_SIZE = 0x10000
HEADER_SIZE = 256

UNIT_1P = "units/cwv_es_musket_custom/cwv_es_musket_custom"
UNIT_3P = "units/cwv_es_musket_custom/cwv_es_musket_custom_3p"
AUTHORED_MATERIAL = "units/cwv_es_musket_custom/cwv_es_musket_custom"
RENDERER = "rifle"
MATERIAL_SLOT = "rifle_mat"
TRIANGLE_COUNT = 16483
BOUND_TOLERANCE_METRES = 0.005

Vector3 = tuple[float, float, float]
Triangle = tuple[int, int, int]
Matrix4 = tuple[
    tuple[float, float, float, float],
    tuple[float, float, float, float],
    tuple[float, float, float, float],
    tuple[float, float, float, float],
]
EXPECTED_RENDERER_WORLD: Matrix4 = (
    (100.0, 0.0, 0.0, 0.0),
    (0.0, 100.0, 0.0, 0.0),
    (0.0, 0.0, 100.0, 0.0),
    (0.0, 0.0, 0.0, 1.0),
)


class ContractFailure(RuntimeError):
    """A deterministic compiled-artifact contract failed."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractFailure(message)


def murmur64a(key: bytes, seed: int = 0) -> int:
    """Stingray IDString64 hash."""
    multiplier = 0xC6A4A7935BD1E995
    rotation = 47
    result = (seed ^ (len(key) * multiplier)) & MASK
    whole_words = len(key) // 8
    for index in range(whole_words):
        word = int.from_bytes(key[index * 8 : index * 8 + 8], "little")
        word = (word * multiplier) & MASK
        word ^= word >> rotation
        word = (word * multiplier) & MASK
        result ^= word
        result = (result * multiplier) & MASK
    tail = key[whole_words * 8 :]
    if tail:
        result ^= int.from_bytes(tail, "little")
        result = (result * multiplier) & MASK
    result ^= result >> rotation
    result = (result * multiplier) & MASK
    result ^= result >> rotation
    return result


def read_bundle(path: Path) -> tuple[int, bytes]:
    raw = path.read_bytes()
    require(len(raw) >= 12, f"compiled root bundle is truncated: {path}")
    bundle_format, inflate_size = struct.unpack_from("<II", raw, 0)
    require(
        bundle_format in SUPPORTED_FORMATS,
        f"compiled root bundle has unsupported format 0x{bundle_format:08X}",
    )

    data = bytearray()
    offset = 12
    block_index = 0
    while offset < len(raw):
        require(offset + 4 <= len(raw), "compiled root bundle has a truncated block header")
        (block_size,) = struct.unpack_from("<I", raw, offset)
        offset += 4
        require(
            block_size != BLOCK_RAW_SIZE,
            "compiled root bundle contains an unsupported raw 0x10000 block",
        )
        require(
            block_size > 0 and offset + block_size <= len(raw),
            f"compiled root bundle block {block_index} is truncated",
        )
        try:
            data.extend(zlib.decompress(raw[offset : offset + block_size]))
        except zlib.error as error:
            raise ContractFailure(
                f"compiled root bundle block {block_index} cannot decompress: {error}"
            ) from error
        offset += block_size
        block_index += 1

    require(
        len(data) >= inflate_size,
        f"compiled root bundle inflated to {len(data)} bytes; header claims {inflate_size}",
    )
    del data[inflate_size:]
    return bundle_format, bytes(data)


def walk_bundle(data: bytes, bundle_format: int) -> list[dict[str, object]]:
    require(len(data) >= 4 + HEADER_SIZE, "compiled root bundle image is truncated")
    (file_count,) = struct.unpack_from("<I", data, 0)
    require(file_count <= 100000, f"compiled root bundle has implausible file count {file_count}")
    offset = 4 + HEADER_SIZE
    index_entries: list[tuple[int, int]] = []

    for index in range(file_count):
        require(offset + 20 <= len(data), f"compiled root index entry {index} is truncated")
        type_hash, name_hash = struct.unpack_from("<QQ", data, offset)
        offset += 16
        if bundle_format == VT2X_FORMAT:
            require(offset + 8 <= len(data), f"compiled VT2X index entry {index} is truncated")
            reserved, _data_size = struct.unpack_from("<II", data, offset)
            require(reserved == 0, f"compiled VT2X index entry {index} has non-zero reserved data")
            offset += 8
        else:
            offset += 4
        index_entries.append((type_hash, name_hash))

    records: list[dict[str, object]] = []
    for index, expected in enumerate(index_entries):
        require(offset + 24 <= len(data), f"compiled resource record {index} is truncated")
        type_hash, name_hash = struct.unpack_from("<QQ", data, offset)
        require(
            (type_hash, name_hash) == expected,
            "compiled root bundle record/index identity mismatch at "
            f"record {index}: expected={expected[0]:016X}/{expected[1]:016X} "
            f"actual={type_hash:016X}/{name_hash:016X}",
        )
        version_count, _stream_offset = struct.unpack_from("<II", data, offset + 16)
        require(version_count <= 64, f"compiled resource {index} has implausible version count {version_count}")
        cursor = offset + 24
        versions: list[tuple[int, int]] = []
        for version in range(version_count):
            require(cursor + 12 <= len(data), f"compiled resource {index} version {version} is truncated")
            _language, size, _stream_size = struct.unpack_from("<III", data, cursor)
            cursor += 12
            versions.append((cursor, size))
        payload_offset = cursor
        payloads: list[bytes] = []
        for version, (_placeholder, size) in enumerate(versions):
            require(
                payload_offset + size <= len(data),
                f"compiled resource {index} payload {version} is truncated",
            )
            payloads.append(data[payload_offset : payload_offset + size])
            payload_offset += size
        records.append({"type": type_hash, "name": name_hash, "payloads": payloads})
        offset = payload_offset

    require(
        offset == len(data),
        f"compiled root bundle walk ended at {offset}; image contains {len(data)} bytes",
    )
    return records


def resource_key(resource_type: str, resource_name: str) -> tuple[int, int]:
    return murmur64a(resource_type.encode()), murmur64a(resource_name.encode())


def require_one_resource(
    records: list[dict[str, object]], resource_type: str, resource_name: str
) -> bytes:
    key = resource_key(resource_type, resource_name)
    hits: list[bytes] = []
    for record in records:
        if (record["type"], record["name"]) == key:
            hits.extend(record["payloads"])  # type: ignore[arg-type]
    require(
        len(hits) == 1,
        f"compiled {resource_type} {resource_name} must occur exactly once; "
        f"found {len(hits)} (bundle is missing, duplicated, or stale)",
    )
    require(len(hits[0]) > 0, f"compiled {resource_type} {resource_name} has an empty payload")
    return hits[0]


@dataclass(frozen=True)
class CompiledSceneNode:
    name_hash: int
    world_transform: Matrix4


@dataclass(frozen=True)
class CompiledMeshGeometry:
    positions: tuple[Vector3, ...]
    triangles: tuple[Triangle, ...]


@dataclass(frozen=True)
class CompiledMeshObject:
    name_hash: int
    node_index: int
    geometry_index: int


@dataclass(frozen=True)
class CompiledUnitStructure:
    nodes: tuple[CompiledSceneNode, ...]
    geometries: tuple[CompiledMeshGeometry, ...]
    meshes: tuple[CompiledMeshObject, ...]


class PackedCursor:
    """Small bounds-checked cursor for the VT2 v189 unit prefix."""

    def __init__(self, payload: bytes):
        self.payload = payload
        self.offset = 0

    def skip(self, size: int) -> None:
        require(size >= 0 and self.offset + size <= len(self.payload), "compiled unit prefix overrun")
        self.offset += size

    def u8(self) -> int:
        require(self.offset + 1 <= len(self.payload), "compiled unit prefix overrun")
        value = struct.unpack_from("<B", self.payload, self.offset)[0]
        self.skip(1)
        return value

    def u16(self) -> int:
        require(self.offset + 2 <= len(self.payload), "compiled unit prefix overrun")
        value = struct.unpack_from("<H", self.payload, self.offset)[0]
        self.skip(2)
        return value

    def u32(self) -> int:
        require(self.offset + 4 <= len(self.payload), "compiled unit prefix overrun")
        value = struct.unpack_from("<I", self.payload, self.offset)[0]
        self.skip(4)
        return value

    def take(self, size: int) -> bytes:
        require(size >= 0 and self.offset + size <= len(self.payload), "compiled unit prefix overrun")
        result = self.payload[self.offset : self.offset + size]
        self.offset += size
        return result

    def byte_array(self) -> bytes:
        return self.take(self.u32())

    def skip_u32_array(self) -> None:
        self.skip(self.u32() * 4)


def compiled_unit_structure(payload: bytes) -> CompiledUnitStructure:
    """Parse scene graph and renderable geometry from a VT2 v189 unit."""
    cursor = PackedCursor(payload)
    version = cursor.u32()
    require(version == 189, f"compiled unit version must be 189; got {version}")

    geometries: list[CompiledMeshGeometry] = []
    for _ in range(cursor.u32()):
        streams: list[tuple[bytes, int, int, int, int]] = []
        for _ in range(cursor.u32()):
            data = cursor.byte_array()
            streams.append((data, cursor.u32(), cursor.u32(), cursor.u32(), cursor.u32()))
        channels = tuple(
            (cursor.u32(), cursor.u32(), cursor.u32(), cursor.u32(), cursor.u8())
            for _ in range(cursor.u32())
        )
        positions = [channel for channel in channels if channel[0] == 0]
        require(len(positions) == 1, f"compiled geometry needs one position channel; got {len(positions)}")
        component, channel_type, _set, stream_index, is_instance = positions[0]
        require(
            component == 0 and channel_type == 17 and is_instance == 0,
            "compiled positions must be non-instanced Half4",
        )
        require(stream_index < len(streams), "compiled position channel refers to a missing stream")
        position_data, validity, stream_type, vertex_count, stride = streams[stream_index]
        require(
            validity == 0 and stream_type == 0 and stride == 8,
            "compiled position stream must be static Half4 array data",
        )
        require(
            len(position_data) == vertex_count * stride,
            "compiled position stream byte count does not match metadata",
        )
        points = tuple(
            tuple(float(value) for value in values[:3])
            for values in struct.iter_unpack("<eeee", position_data)
        )
        require(
            all(math.isfinite(value) for point in points for value in point),
            "compiled position stream contains non-finite coordinates",
        )

        index_validity = cursor.u32()
        index_stream_type = cursor.u32()
        index_format = cursor.u32()
        index_count = cursor.u32()
        index_data = cursor.byte_array()
        require(
            index_validity == 0 and index_stream_type == 0 and index_format in (0, 1),
            "compiled index stream has unsupported metadata",
        )
        index_size = 2 if index_format == 0 else 4
        require(
            len(index_data) == index_count * index_size and index_count % 3 == 0,
            "compiled index stream is not a complete triangle list",
        )
        index_code = "H" if index_format == 0 else "I"
        indices = struct.unpack(f"<{index_count}{index_code}", index_data)
        triangles = tuple(
            tuple(indices[offset : offset + 3])
            for offset in range(0, index_count, 3)
        )
        require(
            not triangles or max(max(triangle) for triangle in triangles) < len(points),
            "compiled index stream exceeds its position stream",
        )
        geometries.append(CompiledMeshGeometry(points, triangles))
        cursor.skip(cursor.u32() * 16)
        cursor.skip(28)
        cursor.skip(cursor.u32() * 4)

    for _ in range(cursor.u32()):
        cursor.skip(cursor.u32() * 64)
        cursor.skip_u32_array()
        for _ in range(cursor.u32()):
            cursor.skip_u32_array()

    cursor.byte_array()
    for _ in range(cursor.u32()):
        cursor.skip(4)
        cursor.skip_u32_array()

    node_count = cursor.u32()
    cursor.skip(node_count * 60)
    world_transforms: list[Matrix4] = []
    for _ in range(node_count):
        values = struct.unpack("<16f", cursor.take(64))
        world_transforms.append(
            tuple(
                tuple(values[column * 4 + row] for column in range(4))
                for row in range(4)
            )
        )
    for _ in range(node_count):
        cursor.u16()
        cursor.u16()
    nodes = tuple(
        CompiledSceneNode(cursor.u32(), world_transform)
        for world_transform in world_transforms
    )

    meshes: list[CompiledMeshObject] = []
    for _ in range(cursor.u32()):
        name_hash = cursor.u32()
        node_index = cursor.u32()
        geometry_index = cursor.u32()
        cursor.skip(8)
        meshes.append(CompiledMeshObject(name_hash, node_index, geometry_index))
        cursor.skip(28)

    shape_extra_sizes = {0: 4, 1: 12, 2: 8, 3: 0, 4: 0, 5: 21, 6: 12}
    for _ in range(cursor.u32()):
        cursor.skip(16)
        for _ in range(cursor.u32()):
            shape_type = cursor.u32()
            require(shape_type in shape_extra_sizes, f"unknown compiled actor shape {shape_type}")
            cursor.skip(8 + 64)
            cursor.byte_array()
            cursor.skip(4 + shape_extra_sizes[shape_type])
        cursor.skip(24)
        require(cursor.u8() in (0, 1), "compiled actor enabled flag is not boolean")

    return CompiledUnitStructure(tuple(nodes), tuple(geometries), tuple(meshes))


def idstring32(value: str) -> int:
    return murmur64a(value.encode()) >> 32


def transform_point(matrix: Matrix4, point: Vector3) -> Vector3:
    x, y, z = point
    return (
        matrix[0][0] * x + matrix[0][1] * y + matrix[0][2] * z + matrix[0][3],
        matrix[1][0] * x + matrix[1][1] * y + matrix[1][2] * z + matrix[1][3],
        matrix[2][0] * x + matrix[2][1] * y + matrix[2][2] * z + matrix[2][3],
    )


def compiled_rifle_geometry(
    structure: CompiledUnitStructure, label: str
) -> tuple[tuple[Vector3, ...], tuple[Triangle, ...]]:
    require(
        len(structure.meshes) == 1,
        f"compiled {label} unit must contain one renderer; got {len(structure.meshes)}",
    )
    mesh = structure.meshes[0]
    require(
        mesh.name_hash == idstring32(RENDERER),
        f"compiled {label} renderer is not {RENDERER!r} (bundle is stale or wrong compile)",
    )
    require(0 <= mesh.node_index < len(structure.nodes), f"compiled {label} renderer has no scene node")
    require(
        1 <= mesh.geometry_index <= len(structure.geometries),
        f"compiled {label} renderer has no geometry",
    )
    geometry = structure.geometries[mesh.geometry_index - 1]
    world = structure.nodes[mesh.node_index].world_transform
    for row in range(4):
        for column in range(4):
            require(
                abs(world[row][column] - EXPECTED_RENDERER_WORLD[row][column])
                <= 0.000001,
                f"compiled {label} renderer world matrix drifted at "
                f"[{row},{column}]: expected={EXPECTED_RENDERER_WORLD[row][column]} "
                f"actual={world[row][column]}",
            )
    return tuple(transform_point(world, point) for point in geometry.positions), geometry.triangles


def compiled_material_pairs(payload: bytes) -> set[tuple[int, int]]:
    """Read the VT2 v189 unit's terminal material-slot table."""
    candidates: list[set[tuple[int, int]]] = []
    for offset in range(max(0, len(payload) - 512), len(payload) - 24):
        count = struct.unpack_from("<I", payload, offset + 8)[0]
        if count == 0 or count > 32:
            continue
        cursor = offset + 12 + count * 12
        if cursor + 16 > len(payload):
            continue
        apex_size = struct.unpack_from("<I", payload, cursor)[0]
        cursor += 4 + apex_size
        if cursor + 12 != len(payload):
            continue
        vehicle_count = struct.unpack_from("<I", payload, cursor)[0]
        if vehicle_count != 0:
            continue
        pairs = {
            struct.unpack_from("<IQ", payload, offset + 12 + index * 12)
            for index in range(count)
        }
        if any(slot == 0 or material == 0 for slot, material in pairs):
            continue
        candidates.append(pairs)
    require(
        len(candidates) == 1,
        f"compiled unit expected one terminal material table; got {len(candidates)}",
    )
    return candidates[0]


def vector3(value: object, field: str) -> Vector3:
    require(isinstance(value, list) and len(value) == 3, f"asset contract {field} must be a 3-vector")
    try:
        result = tuple(float(component) for component in value)
    except (TypeError, ValueError) as error:
        raise ContractFailure(f"asset contract {field} must be numeric") from error
    require(all(math.isfinite(component) for component in result), f"asset contract {field} is non-finite")
    return result  # type: ignore[return-value]


def bounds(points: tuple[Vector3, ...]) -> tuple[Vector3, Vector3]:
    require(bool(points), "compiled rifle renderer has no vertices")
    minimum = tuple(min(point[axis] for point in points) for axis in range(3))
    maximum = tuple(max(point[axis] for point in points) for axis in range(3))
    return minimum, maximum  # type: ignore[return-value]


def require_bounds(
    actual: tuple[Vector3, Vector3], expected: tuple[Vector3, Vector3], label: str
) -> None:
    names = ("min", "max")
    for side in range(2):
        for axis in range(3):
            delta = abs(actual[side][axis] - expected[side][axis])
            require(
                delta <= BOUND_TOLERANCE_METRES,
                f"compiled {label} bounds {names[side]}[{axis}] drifted by {delta:.6f} m: "
                f"expected={expected[side][axis]:.9f} actual={actual[side][axis]:.9f}; "
                "bundle is stale or wrong compile",
            )


def validate(bundle_path: Path, contract_path: Path) -> dict[str, object]:
    require(bundle_path.is_file(), f"compiled root bundle missing: {bundle_path}")
    require(contract_path.is_file(), f"Old Musket asset contract missing: {contract_path}")
    try:
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ContractFailure(f"Old Musket asset contract is unreadable: {error}") from error
    require(
        contract.get("contract") == "cwv_old_musket_native_frame_v3",
        "Old Musket asset contract identity drifted",
    )
    require(
        contract.get("source_polygon_count") == TRIANGLE_COUNT,
        f"Old Musket asset contract must pin {TRIANGLE_COUNT} polygons",
    )
    expected_bounds = (
        vector3(contract.get("output_bounds_min"), "output_bounds_min"),
        vector3(contract.get("output_bounds_max"), "output_bounds_max"),
    )

    bundle_format, image = read_bundle(bundle_path)
    records = walk_bundle(image, bundle_format)
    payload_1p = require_one_resource(records, "unit", UNIT_1P)
    payload_3p = require_one_resource(records, "unit", UNIT_3P)
    require_one_resource(records, "material", AUTHORED_MATERIAL)

    structure_1p = compiled_unit_structure(payload_1p)
    structure_3p = compiled_unit_structure(payload_3p)
    points_1p, triangles_1p = compiled_rifle_geometry(structure_1p, "1P")
    points_3p, triangles_3p = compiled_rifle_geometry(structure_3p, "3P")

    for label, triangles in (("1P", triangles_1p), ("3P", triangles_3p)):
        require(
            len(triangles) == TRIANGLE_COUNT,
            f"compiled {label} rifle has {len(triangles)} triangles; "
            f"expected {TRIANGLE_COUNT} (bundle is stale or wrong compile)",
        )
    require(
        points_1p == points_3p and triangles_1p == triangles_3p,
        "compiled 1P/3P rifle geometry is not exactly identical",
    )

    actual_bounds = bounds(points_1p)
    require_bounds(actual_bounds, expected_bounds, "1P/3P")
    spans = tuple(actual_bounds[1][axis] - actual_bounds[0][axis] for axis in range(3))
    require(
        spans[1] > spans[0] and spans[1] > spans[2],
        f"compiled rifle is not +Y-dominant: spans={spans}",
    )
    require(
        actual_bounds[1][1] > abs(actual_bounds[0][1]),
        "compiled rifle's signed longitudinal extent does not point predominantly +Y",
    )
    # A long-axis test cannot distinguish a 180-degree roll around +Y.  The
    # known-good Empire Handgun has the same signed transverse distribution:
    # more +X than -X and more -Z than +Z.  CWV 0.1.525 had both inequalities
    # reversed and rendered upside down on every live surface.
    require(
        actual_bounds[1][0] > abs(actual_bounds[0][0]),
        "compiled rifle is rolled onto the wrong signed Handgun X half-space",
    )
    require(
        abs(actual_bounds[0][2]) > actual_bounds[1][2],
        "compiled rifle is rolled onto the wrong signed Handgun Z half-space",
    )

    expected_pair = {(idstring32(MATERIAL_SLOT), murmur64a(AUTHORED_MATERIAL.encode()))}
    for label, payload in (("1P", payload_1p), ("3P", payload_3p)):
        actual_pairs = compiled_material_pairs(payload)
        require(
            actual_pairs == expected_pair,
            f"compiled {label} material table does not bind {MATERIAL_SLOT} -> "
            f"{AUTHORED_MATERIAL}: actual={actual_pairs}",
        )

    return {
        "resources": 3,
        "triangles": TRIANGLE_COUNT,
        "vertices": len(points_1p),
        "bounds_min": actual_bounds[0],
        "bounds_max": actual_bounds[1],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    try:
        result = validate(args.bundle, args.contract)
    except ContractFailure as error:
        print(f"[check_cwv_old_musket_compiled_contract] FAILED - {error}", file=sys.stderr)
        return 2
    except Exception as error:  # A parser failure is infrastructure failure, not a false pass.
        print(
            "[check_cwv_old_musket_compiled_contract] INFRASTRUCTURE FAILURE - "
            f"{type(error).__name__}: {error}",
            file=sys.stderr,
        )
        return 99

    if not args.quiet:
        minimum = ",".join(f"{value:.6f}" for value in result["bounds_min"])
        maximum = ",".join(f"{value:.6f}" for value in result["bounds_max"])
        print(
            "[check_cwv_old_musket_compiled_contract] OK - "
            f"3 exact resources, one rifle renderer/view, {result['triangles']} triangles, "
            f"1P/3P geometry exact, bounds=({minimum})..({maximum}), "
            "dominant=+Y, rifle_mat=authored material"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
