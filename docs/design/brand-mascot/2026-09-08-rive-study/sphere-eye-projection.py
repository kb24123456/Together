#!/usr/bin/env python3
"""Make a white capsule eye curve that lies on an orthographically viewed sphere.

Only geometric authoring helpers; no file or Rive mutations. Coordinates use the
CharacterRoot origin (the sphere center), with screen y increasing downward.
Rotation is in Rive degrees. The output uses eight stable cubic anchors:
{x, y, inr, ind, outr, outd}. Angles are degrees, distances are positive.

project_eye(x, y, w, h, rotation) returns CharacterRoot coordinates. For a shape
node translated to (x, y), use local=True and keep that node's rotation at zero.
The requested rotation is already built into the points. Keep shape scale 100.

The center Jacobian of this mapping is the identity: authored eye width,
height, position and rotation remain the first-order design. The non-affine
sphere curvature alone adds the wrapping effect. The same topology works for
open eyes and 7-8 unit high blinks.
"""
from __future__ import annotations

import math
from typing import Callable

RADIUS = 184.0
KAPPA = 4.0 * (math.sqrt(2.0) - 1.0) / 3.0
EPS = 1e-10


def _rotation(degrees: float, point: tuple[float, float]) -> tuple[float, float]:
    angle = math.radians(degrees)
    c, s = math.cos(angle), math.sin(angle)
    return c * point[0] - s * point[1], s * point[0] + c * point[1]


def _surface_map(
    x: float, y: float, radius: float
) -> tuple[Callable, Callable]:
    """Sphere exponential map after the inverse center projection Jacobian.

    A projected local displacement (dx, dy) lifts to the tangent vector
    (dx, dy, -(x*dx+y*dy)/z). This is algebraically the inverse Jacobian of
    longitude/latitude tangent coordinates, without polar basis singularities.
    Exponentiating that vector puts every point on the actual sphere.
    """
    if not all(math.isfinite(v) for v in (x, y, radius)) or radius <= 0:
        raise ValueError("Sphere center coordinates and positive radius must be finite")
    z2 = radius * radius - x * x - y * y
    if z2 <= EPS:
        raise ValueError("Eye center must be inside the visible sphere silhouette")
    z = math.sqrt(z2)

    def quantities(d: tuple[float, float]):
        dx, dy = d
        dz = -(x * dx + y * dy) / z
        q = math.sqrt(dx * dx + dy * dy + dz * dz)
        a = q / radius
        if q < EPS:
            return dz, q, 1.0, 1.0
        return dz, q, math.sin(a) / a, math.cos(a)

    def position(d: tuple[float, float], require_visible: bool = True):
        dz, q, sinc, cosine = quantities(d)
        projected_z = z * cosine + dz * sinc
        if require_visible and projected_z < -1e-8:
            raise ValueError(
                "Eye patch crosses the sphere horizon; move the eye inward or reduce its size"
            )
        return x * cosine + d[0] * sinc, y * cosine + d[1] * sinc

    def derivative(d: tuple[float, float], tangent: tuple[float, float]):
        dz, q, sinc, cosine = quantities(d)
        if q < EPS:
            return tangent
        tdz = -(x * tangent[0] + y * tangent[1]) / z
        dq = (d[0] * tangent[0] + d[1] * tangent[1] + dz * tdz) / q
        a = q / radius
        normal_factor = -math.sin(a) * dq / radius
        tangent_factor = (cosine - sinc) * dq / q
        return (
            x * normal_factor + tangent[0] * sinc + d[0] * tangent_factor,
            y * normal_factor + tangent[1] * sinc + d[1] * tangent_factor,
        )

    return position, derivative


def _capsule(w: float, h: float):
    """Eight rounded-rectangle anchors with cubic handles and fixed directions.

    Repeated anchors represent zero length edges at either capsule orientation.
    Straight source segments also use cubic handles so the sphere can bend them.
    """
    hx, hy = w / 2.0, h / 2.0
    r = min(hx, hy)
    k = KAPPA * r
    horizontal = (w - 2.0 * r) / 3.0
    vertical = (h - 2.0 * r) / 3.0
    anchors = [
        (-hx+r, -hy), (hx-r, -hy), (hx, -hy+r), (hx, hy-r),
        (hx-r, hy), (-hx+r, hy), (-hx, hy-r), (-hx, -hy+r),
    ]
    incoming = [(-k,0), (-horizontal,0), (0,-k), (0,-vertical),
                (k,0), (horizontal,0), (0,k), (0,vertical)]
    outgoing = [(horizontal,0), (k,0), (0,vertical), (0,k),
                (-horizontal,0), (-k,0), (0,-vertical), (0,-k)]
    # Semantic references keep angles continuous through +/-180 and collapsed
    # edges; atan2(0, 0) must not set arbitrary directions during a blink.
    incoming_angles = [180,180,-90,-90,0,0,90,90]
    outgoing_angles = [0,0,90,90,180,180,-90,-90]
    return anchors, incoming, outgoing, incoming_angles, outgoing_angles


def _angle_distance(vector: tuple[float, float], reference: float):
    distance = math.hypot(*vector)
    if distance < EPS:
        return reference, 0.0
    angle = math.degrees(math.atan2(vector[1], vector[0]))
    angle += 360.0 * math.floor((reference - angle + 180.0) / 360.0)
    return angle, distance


def project_eye(
    x: float, y: float, w: float, h: float, rotation: float,
    *, radius: float = RADIUS, local: bool = False,
) -> list[dict[str, float]]:
    """Return eight sphere-wrapped cubic vertices using six Rive properties.

    Incoming/outgoing handles are the analytic differential of the surface
    mapping at each anchor, applied to its original Bezier handle. This retains
    tangent continuity and avoids the distortions caused by merely projecting
    Bezier control points. Cubics approximate the exact spherical curves.
    """
    if not all(math.isfinite(v) for v in (w, h, rotation)) or min(w, h) <= 0:
        raise ValueError("Eye dimensions must be positive and dimensions/rotation finite")
    position, derivative = _surface_map(x, y, radius)
    anchors, incoming, outgoing, in_refs, out_refs = _capsule(w, h)
    result = []
    for point, handle_in, handle_out, ref_in, ref_out in zip(
        anchors, incoming, outgoing, in_refs, out_refs
    ):
        d = _rotation(rotation, point)
        px, py = position(d)
        mapped_in = derivative(d, _rotation(rotation, handle_in))
        mapped_out = derivative(d, _rotation(rotation, handle_out))
        inr, ind = _angle_distance(mapped_in, ref_in + rotation)
        outr, outd = _angle_distance(mapped_out, ref_out + rotation)
        result.append({
            "x": px - (x if local else 0.0),
            "y": py - (y if local else 0.0),
            "inr": inr, "ind": ind, "outr": outr, "outd": outd,
        })
    return result


def as_rive_properties(vertices: list[dict[str, float]]) -> list[dict[str, float]]:
    """Convert readable names to CubicDetachedVertex numeric property keys."""
    keys = {"x":"24", "y":"25", "inr":"84", "ind":"85", "outr":"86", "outd":"87"}
    return [{keys[k]: value for k, value in vertex.items()} for vertex in vertices]


def absolute_handles(vertex: dict[str, float]) -> dict[str, float]:
    """Alternative format for path creation APIs accepting absolute controls."""
    x, y = vertex["x"], vertex["y"]
    ia, oa = math.radians(vertex["inr"]), math.radians(vertex["outr"])
    return {"x":x, "y":y,
            "inX":x+math.cos(ia)*vertex["ind"],
            "inY":y+math.sin(ia)*vertex["ind"],
            "outX":x+math.cos(oa)*vertex["outd"],
            "outY":y+math.sin(oa)*vertex["outd"]}


def sample_outline(vertices, samples_per_segment=24):
    points = []
    controls = [absolute_handles(v) for v in vertices]
    for index, start in enumerate(controls):
        end = controls[(index + 1) % len(controls)]
        for step in range(samples_per_segment):
            t = step / samples_per_segment
            u = 1 - t
            points.append((
                u**3*start["x"]+3*u*u*t*start["outX"]+3*u*t*t*end["inX"]+t**3*end["x"],
                u**3*start["y"]+3*u*u*t*start["outY"]+3*u*t*t*end["inY"]+t**3*end["y"],
            ))
    return points


def _demo():
    poses = [
        ("front", 0, 0, 30, 86, 0),
        ("farRight", 126, -44, 30, 86, -22),
        ("farRightBlink", 126, -44, 30, 7.5, -22),
    ]
    for name, x, y, w, h, rotation in poses:
        vertices = project_eye(x, y, w, h, rotation)
        points = sample_outline(vertices)
        bounds = (min(p[0] for p in points), min(p[1] for p in points),
                  max(p[0] for p in points), max(p[1] for p in points))
        position, _ = _surface_map(x, y, RADIUS)
        top = position(_rotation(rotation, (0, -h/2)))
        bottom = position(_rotation(rotation, (0, h/2)))
        bend = ((top[0]+bottom[0])/2-x, (top[1]+bottom[1])/2-y)
        assert len(vertices) == 8
        assert all(math.isfinite(value) for v in vertices for value in v.values())
        assert all(v["ind"] >= 0 and v["outd"] >= 0 for v in vertices)
        print(f"{name}: bounds={tuple(round(v,3) for v in bounds)} "
              f"cap_midpoint_bend={tuple(round(v,3) for v in bend)} "
              f"anchors={len(vertices)}")
    # Numerical differential check: Jacobian is identity at the eye center.
    p, derivative = _surface_map(126, -44, RADIUS)
    assert derivative((0,0), (1,0)) == (1,0)
    assert derivative((0,0), (0,1)) == (0,1)
    d, v, epsilon = (12.0, 25.0), (0.3, -0.7), 1e-5
    a = p((d[0]+epsilon*v[0], d[1]+epsilon*v[1]))
    b = p((d[0]-epsilon*v[0], d[1]-epsilon*v[1]))
    numeric = ((a[0]-b[0])/(2*epsilon), (a[1]-b[1])/(2*epsilon))
    analytic = derivative(d, v)
    assert max(abs(numeric[i]-analytic[i]) for i in (0,1)) < 1e-7
    # Opening/closing through circular shape keeps the topology and handle
    # angle branch stable. No 360-degree interpolation spins are introduced.
    previous = None
    largest_step = 0.0
    for frame in range(201):
        h = 86 - (86 - 7.5) * frame / 200
        current = project_eye(126, -44, 30, h, -22)
        if previous:
            largest_step = max(largest_step, *(abs(a[k]-b[k])
                for a,b in zip(current,previous) for k in ("inr","outr")))
        previous = current
    assert largest_step < 30
    print(f"checks: center Jacobian identity; analytic derivative verified; "
          f"blink angle largest step={largest_step:.3f} degrees")


if __name__ == "__main__":
    _demo()
