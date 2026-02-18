// Pimoroni Inky Impression 13.3" — board model
// All dimensions in mm

// --- Parameters ---

// Board outer dimensions
board_width  = 296.70;
board_height = 210.00;
board_thickness = 1.6; // standard PCB, will adjust later

// Corner mounting holes
hole_inset    = 3.00;  // from board edge to hole center
hole_diameter = 2.7;   // M2.5 clearance hole (adjust if needed)

// Corner rounding (estimated, not dimensioned in schematic)
corner_radius = 2.0;

// Viewable area (not centered — connector side has more margin)
viewable_width  = 270.40;
viewable_height = 202.80;
viewable_x = 9.00;  // from left edge
viewable_y = (board_height - viewable_height) / 2; // centered vertically

// --- Derived ---
hole_radius = hole_diameter / 2;

// Hole positions (from bottom-left origin)
hole_positions = [
    [hole_inset, hole_inset],
    [board_width - hole_inset, hole_inset],
    [hole_inset, board_height - hole_inset],
    [board_width - hole_inset, board_height - hole_inset],
];

// --- Model ---

module board() {
    difference() {
        // Board body with rounded corners
        linear_extrude(height = board_thickness)
            offset(r = corner_radius)
            offset(delta = -corner_radius)
            square([board_width, board_height]);

        // Corner mounting holes
        for (pos = hole_positions) {
            translate([pos[0], pos[1], -0.1])
                cylinder(h = board_thickness + 0.2, r = hole_radius, $fn = 32);
        }
    }
}

color("SteelBlue") board();

// Viewable area indicator
color("DarkSlateGray")
    translate([viewable_x, viewable_y, board_thickness - 0.01])
    linear_extrude(height = 0.02)
    square([viewable_width, viewable_height]);
