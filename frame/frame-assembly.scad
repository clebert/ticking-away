// IKEA 32x32cm frame — two-part 3D printed backplate for Inky Impression 13.3"
// All dimensions in mm
//
// === Assembly (front to back) ===
// 1. IKEA frame (glass + wood border)
// 2. Paper mat with 200x200mm opening (original IKEA mat, reused)
// 3. Display board (screen faces forward through mat opening)
// 4. 3D printed backplate (this model — two parts, replaces original hardboard)
// 5. IKEA metal clips (original clips hold everything in the frame)
//
// === Two-part design ===
// The backplate is two separate prints, glued together:
//
// Part 1: Backplate plate (3mm flat)
//   - 320x320mm, 3mm thick, with a through-hole for the board (296.7x210mm).
//   - Replaces the original IKEA hardboard, same 3mm thickness.
//   - IKEA metal clips grip the outer edges.
//   - Split into 4 quadrants with dovetail joints for the 180x180mm print bed.
//   - Print front-face down.
//
// Part 2: Corner brackets (4 pieces, glued to plate back)
//   - Each bracket has a flat base (3mm, glues to plate back) that overlaps
//     the through-hole corner, forming the ledge the board sits on.
//   - Board drops into the through-hole and rests on the base; its front
//     face is flush with the plate front face (both 3mm thick).
//   - Knobs (ø1.9mm, 1.2mm tall) project from the base top into the board's
//     mounting holes for board alignment.
//   - Registration pins: 2 knobs on the plate back + 2 matching holes in each
//     bracket base align the bracket for gluing without the board in place.
//   - Print base-down — no support needed.
//   - Each bracket fits the 180x180mm print bed individually.
//
// Cross-section at a corner:
//
//   mat / front face (top)
//   ────────────┐         ┌────── plate front face
//               │ plate   │ board (3mm, flush with plate front)
//   ──────●─────┘ 3mm   ● │ ← knob (into board mounting hole)
//         ○ ┌─────────────┤
//           │ bracket base (glued to plate back)
//           └─────────────┘
//   ● = registration pin (plate knob into bracket hole)
//   ○ = registration hole in bracket
//
// === Print constraints ===
// Printer: Bambu Lab A1 Mini, build volume 180x180x180mm.
// Nozzle: 0.4mm. Layer height: 0.20mm.
//
// Nozzle rules of thumb (0.4mm):
//   - Minimum wall: 0.8mm (2 perimeters), comfortable: 1.2mm (3 perimeters)
//   - Minimum gap (clearance): 0.4mm (1 nozzle width) to avoid bridging
//   - Features < 2mm may lose detail; features < 0.8mm won't print
//
// The 320x320mm plate is split into 4 interlocking quadrants (~160x160mm each)
// with dovetail edges for assembly.
//
// === Export ===
// print_part selects what to render for STL export:
//   0 = assembly view (default)
//   1–4 = plate quadrant (BL, BR, TL, TR)
//   5 = all 4 corner brackets
//
// Generate preview PNG:
//   xvfb-run -a openscad --imgsize 1024,1024 --autocenter --viewall --colorscheme BeforeDawn -o frame-assembly.png frame-assembly.scad
//
// Export all STLs:
//   for p in 1 2 3 4; do xvfb-run -a openscad -D "print_part=$p" -o quadrant$p.stl frame-assembly.scad; done
//   xvfb-run -a openscad -D "print_part=5" -o brackets.stl frame-assembly.scad
//
// IMPORTANT: After any change to this file, re-run the PNG and STL export
// commands above to keep the generated files in sync.

// --- IKEA Frame ---
// LOMVIKEN 32x32 cm, black
// https://www.ikea.com/de/de/p/lomviken-rahmen-schwarz-00335852/
frame_size = 320.00;
plate_thickness = 3.0;

// Mat opening (centered in frame)
mat_opening = 200.00;

// --- Display board (Pimoroni Inky Impression 13.3") ---
board_width  = 296.70;
board_height = 210.00;
board_thickness = 3.0;

// Corner mounting holes
hole_inset    = 3.00;
hole_diameter = 2.7;

// Corner rounding (estimated, not dimensioned in schematic)
corner_radius = 2.0;

// Viewable area (not centered on board — connector side has more margin)
viewable_width  = 270.40;
viewable_height = 202.80;
viewable_x = 9.00;
viewable_y = (board_height - viewable_height) / 2;

// --- Board positioning (viewable area centered in mat opening) ---
viewable_center_x = viewable_x + viewable_width / 2;
viewable_center_y = viewable_y + viewable_height / 2;
mat_center = frame_size / 2;
board_x = mat_center - viewable_center_x; // 15.80
board_y = mat_center - viewable_center_y; // 55.00

// --- Corner brackets ---
bracket_base = 3.0;            // base thickness (glued to plate back)
bracket_pad  = 14.0;           // base overlap onto board area (through-hole)
bracket_rim  = 10.0;           // base overlap onto plate area (glue surface)

// Alignment knobs (board mounting holes)
knob_diameter = 1.9;
knob_height   = 1.2;

// Registration pins (plate-to-bracket alignment for gluing)
// Two pins per corner, one in each arm of the L-shaped rim area.
function reg_pin_positions(cx, cy) = [
    [(cx == 0) ? bracket_rim / 2 : bracket_pad + bracket_rim / 2,
     (cy == 0) ? bracket_rim + bracket_pad / 2 : bracket_pad / 2],
    [(cx == 0) ? bracket_rim + bracket_pad / 2 : bracket_pad / 2,
     (cy == 0) ? bracket_rim / 2 : bracket_pad + bracket_rim / 2]
];

// --- Dovetail interlock ---
// Trapezoidal (dovetail) tabs: narrower at the base, wider at the tip.
// Once assembled from above (Z axis), the angled sides prevent separation
// in both X and Y. Only Z separation is possible — blocked by IKEA clips.
//
// All tab dimensions are derived from just two ratios plus the border width:
//   dovetail_angle — taper half-angle (consistent interlock across all joints)
//   tab_fill       — fraction of border width used by the slot tip
//
// Formula per border:
//   tab_tip  = border × tab_fill − 2 × joint_clearance
//   tab_base = tab_tip − 2 × tab_depth × tan(dovetail_angle)
//   wall     = border × (1 − tab_fill) / 2
joint_clearance = 0.2;
tab_depth       = 5.0;
dovetail_angle  = 15;
tab_fill        = 0.6;
half = frame_size / 2;

// Through-hole boundaries (= board position, no clearance)
hole_x_min = board_x;                       // 15.80
hole_x_max = board_x + board_width;         // 312.50
hole_y_min = board_y;                       // 55.00
hole_y_max = board_y + board_height;        // 265.00

// Border widths (solid zones where dovetail tabs are placed)
border_vert  = hole_y_min;                  // 55.00 (bottom = top)
border_left  = hole_x_min;                  // 15.80
border_right = frame_size - hole_x_max;     // 7.50

// Derived dovetail dimensions
dovetail_expansion = tab_depth * tan(dovetail_angle);
function dt_tip(border)  = border * tab_fill - 2 * joint_clearance;
function dt_base(border) = dt_tip(border) - 2 * dovetail_expansion;
function dt_wall(border) = border * (1 - tab_fill) / 2;

// Tab positions — centered in solid border zones
vtab_y_bot   = hole_y_min / 2;              // ~27.50 (bottom border)
vtab_y_top   = (hole_y_max + frame_size) / 2; // ~292.50 (top border)
htab_x_left  = hole_x_min / 2;              // ~7.90 (left border)
htab_x_right = (hole_x_max + frame_size) / 2; // ~316.25 (right border)

// --- Modules ---

module board() {
    hole_positions = [
        [hole_inset, hole_inset],
        [board_width - hole_inset, hole_inset],
        [hole_inset, board_height - hole_inset],
        [board_width - hole_inset, board_height - hole_inset],
    ];

    difference() {
        linear_extrude(height = board_thickness)
            offset(r = corner_radius)
            offset(delta = -corner_radius)
            square([board_width, board_height]);

        for (pos = hole_positions)
            translate([pos[0], pos[1], -0.1])
                cylinder(h = board_thickness + 0.2, r = hole_diameter / 2, $fn = 32);
    }
}

// --- 2D quadrant boundary with dovetail tab edges ---
// qx: 0=left, 1=right  qy: 0=bottom, 1=top
//
// Vertical split (x=160): tabs in bottom and top solid borders.
//   Left quadrants (qx==0) own the tabs, right quadrants get slots.
// Horizontal split (y=160): tabs in left AND right solid borders.
//   Bottom quadrants (qy==0) own the tabs, top quadrants get slots.
//
// All tabs assemble from above (Z axis). The dovetail angle prevents
// separation in X and Y once the IKEA clips hold the Z axis.

// Centered dovetail trapezoid: base (narrow) at x=-d/2, tip (wide) at x=+d/2
// Pass the border width — tip and base are computed from the shared ratios.
module dovetail_tab_2d(border) {
    w_tip  = dt_tip(border);
    w_base = dt_base(border);
    d = tab_depth;
    polygon([
        [-d/2, -w_base/2],
        [-d/2,  w_base/2],
        [ d/2,  w_tip/2],
        [ d/2, -w_tip/2]
    ]);
}

module dovetail_slot_2d(border) {
    w_tip  = dt_tip(border);
    w_base = dt_base(border);
    d = tab_depth;
    cl = joint_clearance;
    polygon([
        [-d/2 - cl, -w_base/2 - cl],
        [-d/2 - cl,  w_base/2 + cl],
        [ d/2 + cl,  w_tip/2 + cl],
        [ d/2 + cl, -w_tip/2 - cl]
    ]);
}

module quadrant_2d(qx, qy) {
    // Vertical split tab y-position for this quadrant's half
    vtab_y = (qy == 0) ? vtab_y_bot : vtab_y_top;

    difference() {
        union() {
            // Base square for this quadrant
            translate([qx * half, qy * half])
                square([half, half]);

            // Left quadrants (qx==0): add tab on right edge (vertical split)
            if (qx == 0)
                translate([half, vtab_y])
                    dovetail_tab_2d(border_vert);

            // Bottom-left (qx==0, qy==0): add small tab on top edge (left border)
            if (qy == 0 && qx == 0)
                translate([htab_x_left, half])
                    rotate([0, 0, 90])
                    dovetail_tab_2d(border_left);

            // Bottom-right (qx==1, qy==0): add narrow tab on top edge (right border)
            if (qy == 0 && qx == 1)
                translate([htab_x_right, half])
                    rotate([0, 0, 90])
                    dovetail_tab_2d(border_right);
        }

        // Right quadrants (qx==1): cut slot on left edge (vertical split)
        if (qx == 1)
            translate([half, vtab_y])
                dovetail_slot_2d(border_vert);

        // Top-left (qx==0, qy==1): cut slot on bottom edge (left border)
        if (qy == 1 && qx == 0)
            translate([htab_x_left, half])
                rotate([0, 0, 90])
                dovetail_slot_2d(border_left);

        // Top-right (qx==1, qy==1): cut slot on bottom edge (right border)
        if (qy == 1 && qx == 1)
            translate([htab_x_right, half])
                rotate([0, 0, 90])
                dovetail_slot_2d(border_right);
    }
}

// --- Full backplate plate (before quadrant splitting) ---

module backplate_plate() {
    difference() {
        cube([frame_size, frame_size, plate_thickness]);
        translate([board_x, board_y, -0.1])
            cube([board_width, board_height, plate_thickness + 0.2]);
    }

    // Registration knobs on plate back face (received by bracket holes)
    for (i = [0:3]) {
        cx = corner_grid[i][0];
        cy = corner_grid[i][1];
        origin = bracket_origin(cx, cy);
        for (pos = reg_pin_positions(cx, cy))
            translate([origin[0] + pos[0], origin[1] + pos[1], -knob_height])
                cylinder(h = knob_height, r = knob_diameter / 2, $fn = 24);
    }
}

// --- Plate quadrant: slice with dovetail tab edges ---

module plate_quadrant(qx, qy) {
    intersection() {
        backplate_plate();
        translate([0, 0, -knob_height - 1])
            linear_extrude(height = plate_thickness + knob_height + 2)
            quadrant_2d(qx, qy);
    }
}

// --- Corner bracket ---
// Generated at local origin (base corner at [0,0,0]).
// cx: 0=left, 1=right  cy: 0=bottom, 1=top

module corner_bracket(cx, cy) {
    base_w = bracket_pad + bracket_rim;
    base_h = bracket_pad + bracket_rim;
    reg_hole_r = (knob_diameter + 2 * joint_clearance) / 2;

    difference() {
        union() {
            // Base (glued to plate back)
            cube([base_w, base_h, bracket_base]);

            // Alignment knob (projects from base top into board mounting hole)
            knob_x = (cx == 0) ? bracket_rim + hole_inset : bracket_pad - hole_inset;
            knob_y = (cy == 0) ? bracket_rim + hole_inset : bracket_pad - hole_inset;
            translate([knob_x, knob_y, bracket_base])
                cylinder(h = knob_height, r = knob_diameter / 2, $fn = 24);
        }

        // Registration holes (receive plate knobs for alignment during gluing)
        for (pos = reg_pin_positions(cx, cy))
            translate([pos[0], pos[1], bracket_base - knob_height - 0.1])
                cylinder(h = knob_height + 0.2, r = reg_hole_r, $fn = 24);
    }
}

// Bracket world-space origin for assembly placement
function bracket_origin(cx, cy) = [
    min(board_x + cx * (board_width - bracket_pad),
        (cx == 0) ? board_x - bracket_rim : board_x + board_width),
    min(board_y + cy * (board_height - bracket_pad),
        (cy == 0) ? board_y - bracket_rim : board_y + board_height)
];

// --- View mode ---
// print_part:
//   0 = assembly view (all parts)
//   1–4 = plate quadrant for STL export (BL, BR, TL, TR)
//   5 = all 4 corner brackets arranged for printing

print_part = 0;
show_board = false;
show_split = true;
explode    = false;
split_gap  = 5;

// Corner/quadrant grid: [x, y] indexed 1–4 / 5–8 (BL, BR, TL, TR)
corner_grid = [[0, 0], [1, 0], [0, 1], [1, 1]];

if (print_part >= 1 && print_part <= 4) {
    // Export single plate quadrant at origin
    qx = corner_grid[print_part - 1][0];
    qy = corner_grid[print_part - 1][1];
    translate([-qx * half, -qy * half, 0])
        plate_quadrant(qx, qy);

} else if (print_part == 5) {
    // All 4 brackets in a 2x2 grid with 5mm spacing
    bracket_size = bracket_pad + bracket_rim;
    bracket_spacing = 5;
    for (i = [0:3]) {
        cx = corner_grid[i][0];
        cy = corner_grid[i][1];
        translate([cx * (bracket_size + bracket_spacing),
                   cy * (bracket_size + bracket_spacing), 0])
            corner_bracket(cx, cy);
    }

} else {
    // Assembly view
    explode_offset = explode ? 20 : 0;

    // Plate quadrants
    for (i = [0:3]) {
        qx = corner_grid[i][0];
        qy = corner_grid[i][1];
        gap = show_split
            ? [(qx - 0.5) * split_gap, (qy - 0.5) * split_gap, 0]
            : [0, 0, 0];
        col = (qx + qy) % 2 == 0 ? "White" : "WhiteSmoke";
        translate(gap + [0, 0, explode_offset])
            color(col) plate_quadrant(qx, qy);
    }

    // Corner brackets
    for (i = [0:3]) {
        cx = corner_grid[i][0];
        cy = corner_grid[i][1];
        origin = bracket_origin(cx, cy);
        translate([origin[0], origin[1], -bracket_base - explode_offset])
            color("Tomato", 0.8) corner_bracket(cx, cy);
    }

    // Board (reference only)
    if (show_board)
        translate([board_x, board_y, plate_thickness])
            color("SteelBlue") board();
}
