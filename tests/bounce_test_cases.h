#pragma once

#include <stdbool.h>

typedef struct {
  int hour;
  float minute;
  bool expect_bounce;
} TestCase;

static const TestCase test_cases[] = {
    // =========================================================================
    // HOUR 0 TESTS
    // =========================================================================

    // ----- v0 (top vertex) region around :00 -----
    {11, 59.8f, true},
    {11, 59.9f, true},
    {0, 0.0f, true},
    {0, 0.1f, true},
    {0, 0.2f, true},

    // ----- v1 (bottom-right vertex) region around :20 -----
    {0, 19.8f, true},
    {0, 19.9f, true},
    {0, 20.0f, true},
    {0, 20.1f, true},
    {0, 20.2f, false},

    // ----- v2 (bottom-left vertex) region around :40 -----
    {0, 39.8f, false},
    {0, 39.9f, false},
    {0, 40.0f, false},
    {0, 40.1f, false},
    {0, 40.2f, false},

    // ----- Discrete minutes (face midpoints) -----
    {0, 10.0f, true},  // face_0 middle
    {0, 30.0f, false}, // face_1 middle
    {0, 50.0f, false}, // face_2 middle

    // =========================================================================
    // HOUR 1 TESTS
    // =========================================================================

    // ----- v0 (top vertex) region around :00 -----
    {0, 59.8f, false},
    {0, 59.9f, true},
    {1, 0.0f, true},
    {1, 0.1f, true},
    {1, 0.2f, true},

    // ----- v1 (bottom-right vertex) region around :20 -----
    {1, 19.8f, true},
    {1, 19.9f, true},
    {1, 20.0f, true},
    {1, 20.1f, true},
    {1, 20.2f, false},

    // ----- v2 (bottom-left vertex) region around :40 -----
    {1, 39.8f, false},
    {1, 39.9f, false},
    {1, 40.0f, false},
    {1, 40.1f, false},
    {1, 40.2f, false},

    // ----- Discrete minutes (face midpoints) -----
    {1, 10.0f, true},
    {1, 30.0f, false},
    {1, 50.0f, false},

    // =========================================================================
    // HOUR 2 TESTS
    // =========================================================================

    // ----- v0 (top vertex) region around :00 -----
    {1, 59.8f, false},
    {1, 59.9f, true},
    {2, 0.0f, true},
    {2, 0.1f, true},
    {2, 0.2f, true},

    // ----- v1 (bottom-right vertex) region around :20 -----
    {2, 19.8f, true},
    {2, 19.9f, true},
    {2, 20.0f, true},
    {2, 20.1f, true},
    {2, 20.2f, false},

    // ----- v2 (bottom-left vertex) region around :40 -----
    {2, 39.8f, false},
    {2, 39.9f, false},
    {2, 40.0f, false},
    {2, 40.1f, false},
    {2, 40.2f, false},

    // ----- Discrete minutes (face midpoints) -----
    {2, 10.0f, true},
    {2, 30.0f, false},
    {2, 50.0f, false},

    // =========================================================================
    // HOUR 3 TESTS
    // =========================================================================

    // ----- v0 (top vertex) region around :00 -----
    {2, 59.8f, false},
    {2, 59.9f, true},
    {3, 0.0f, true},
    {3, 0.1f, true},
    {3, 0.2f, true},

    // ----- v1 (bottom-right vertex) region around :20 -----
    {3, 19.8f, true},
    {3, 19.9f, true},
    {3, 20.0f, true},
    {3, 20.1f, true},
    {3, 20.2f, false},

    // ----- v2 (bottom-left vertex) region around :40 -----
    {3, 39.8f, false},
    {3, 39.9f, false},
    {3, 40.0f, false},
    {3, 40.1f, false},
    {3, 40.2f, false},

    // ----- Discrete minutes (face midpoints) -----
    {3, 10.0f, true},
    {3, 30.0f, false},
    {3, 50.0f, false},

    // =========================================================================
    // HOUR 4 TESTS
    // =========================================================================

    // ----- v0 (top vertex) region around :00 -----
    {3, 59.8f, false},
    {3, 59.9f, false},
    {4, 0.0f, false},
    {4, 0.1f, false},
    {4, 0.2f, false},

    // ----- v1 (bottom-right vertex) region around :20 -----
    {4, 19.8f, false},
    {4, 19.9f, true},
    {4, 20.0f, true},
    {4, 20.1f, true},
    {4, 20.2f, true},

    // ----- v2 (bottom-left vertex) region around :40 -----
    {4, 39.8f, true},
    {4, 39.9f, true},
    {4, 40.0f, true},
    {4, 40.1f, true},
    {4, 40.2f, false},

    // ----- Discrete minutes (face midpoints) -----
    {4, 10.0f, false},
    {4, 30.0f, true},
    {4, 50.0f, false},

    // =========================================================================
    // HOUR 5 TESTS
    // =========================================================================

    // ----- v0 (top vertex) region around :00 -----
    {4, 59.8f, false},
    {4, 59.9f, false},
    {5, 0.0f, false},
    {5, 0.1f, false},
    {5, 0.2f, false},

    // ----- v1 (bottom-right vertex) region around :20 -----
    {5, 19.8f, false},
    {5, 19.9f, true},
    {5, 20.0f, true},
    {5, 20.1f, true},
    {5, 20.2f, true},

    // ----- v2 (bottom-left vertex) region around :40 -----
    {5, 39.8f, true},
    {5, 39.9f, true},
    {5, 40.0f, true},
    {5, 40.1f, true},
    {5, 40.2f, false},

    // ----- Discrete minutes (face midpoints) -----
    {5, 10.0f, false},
    {5, 30.0f, true},
    {5, 50.0f, false},

    // =========================================================================
    // HOUR 6 TESTS
    // =========================================================================

    // ----- v0 (top vertex) region around :00 -----
    {5, 59.8f, false},
    {5, 59.9f, false},
    {6, 0.0f, false},
    {6, 0.1f, false},
    {6, 0.2f, false},

    // ----- v1 (bottom-right vertex) region around :20 -----
    {6, 19.8f, false},
    {6, 19.9f, true},
    {6, 20.0f, true},
    {6, 20.1f, true},
    {6, 20.2f, true},

    // ----- v2 (bottom-left vertex) region around :40 -----
    {6, 39.8f, true},
    {6, 39.9f, true},
    {6, 40.0f, true},
    {6, 40.1f, true},
    {6, 40.2f, false},

    // ----- Discrete minutes (face midpoints) -----
    {6, 10.0f, false},
    {6, 30.0f, true},
    {6, 50.0f, false},

    // =========================================================================
    // HOUR 7 TESTS
    // =========================================================================

    // ----- v0 (top vertex) region around :00 -----
    {6, 59.8f, false},
    {6, 59.9f, false},
    {7, 0.0f, false},
    {7, 0.1f, false},
    {7, 0.2f, false},

    // ----- v1 (bottom-right vertex) region around :20 -----
    {7, 19.8f, false},
    {7, 19.9f, true},
    {7, 20.0f, true},
    {7, 20.1f, true},
    {7, 20.2f, true},

    // ----- v2 (bottom-left vertex) region around :40 -----
    {7, 39.8f, true},
    {7, 39.9f, true},
    {7, 40.0f, true},
    {7, 40.1f, true},
    {7, 40.2f, false},

    // ----- Discrete minutes (face midpoints) -----
    {7, 10.0f, false},
    {7, 30.0f, true},
    {7, 50.0f, false},

    // =========================================================================
    // HOUR 8 TESTS
    // =========================================================================

    // ----- v0 (top vertex) region around :00 -----
    {7, 59.8f, false},
    {7, 59.9f, false},
    {8, 0.0f, false},
    {8, 0.1f, false},
    {8, 0.2f, false},

    // ----- v1 (bottom-right vertex) region around :20 -----
    {8, 19.8f, false},
    {8, 19.9f, false},
    {8, 20.0f, false},
    {8, 20.1f, false},
    {8, 20.2f, false},

    // ----- v2 (bottom-left vertex) region around :40 -----
    {8, 39.8f, false},
    {8, 39.9f, true},
    {8, 40.0f, true},
    {8, 40.1f, true},
    {8, 40.2f, true},

    // ----- Discrete minutes (face midpoints) -----
    {8, 10.0f, false},
    {8, 30.0f, false},
    {8, 50.0f, true},

    // =========================================================================
    // HOUR 9 TESTS
    // =========================================================================

    // ----- v0 (top vertex) region around :00 -----
    {8, 59.8f, true},
    {8, 59.9f, true},
    {9, 0.0f, true},
    {9, 0.1f, true},
    {9, 0.2f, false},

    // ----- v1 (bottom-right vertex) region around :20 -----
    {9, 19.8f, false},
    {9, 19.9f, false},
    {9, 20.0f, false},
    {9, 20.1f, false},
    {9, 20.2f, false},

    // ----- v2 (bottom-left vertex) region around :40 -----
    {9, 39.8f, false},
    {9, 39.9f, true},
    {9, 40.0f, true},
    {9, 40.1f, true},
    {9, 40.2f, true},

    // ----- Discrete minutes (face midpoints) -----
    {9, 10.0f, false},
    {9, 30.0f, false},
    {9, 50.0f, true},

    // =========================================================================
    // HOUR 10 TESTS
    // =========================================================================

    // ----- v0 (top vertex) region around :00 -----
    {9, 59.8f, true},
    {9, 59.9f, true},
    {10, 0.0f, true},
    {10, 0.1f, true},
    {10, 0.2f, false},

    // ----- v1 (bottom-right vertex) region around :20 -----
    {10, 19.8f, false},
    {10, 19.9f, false},
    {10, 20.0f, false},
    {10, 20.1f, false},
    {10, 20.2f, false},

    // ----- v2 (bottom-left vertex) region around :40 -----
    {10, 39.8f, false},
    {10, 39.9f, true},
    {10, 40.0f, true},
    {10, 40.1f, true},
    {10, 40.2f, true},

    // ----- Discrete minutes (face midpoints) -----
    {10, 10.0f, false},
    {10, 30.0f, false},
    {10, 50.0f, true},

    // =========================================================================
    // HOUR 11 TESTS
    // =========================================================================

    // ----- v0 (top vertex) region around :00 -----
    {10, 59.8f, true},
    {10, 59.9f, true},
    {11, 0.0f, true},
    {11, 0.1f, true},
    {11, 0.2f, false},

    // ----- v1 (bottom-right vertex) region around :20 -----
    {11, 19.8f, false},
    {11, 19.9f, false},
    {11, 20.0f, false},
    {11, 20.1f, false},
    {11, 20.2f, false},

    // ----- v2 (bottom-left vertex) region around :40 -----
    {11, 39.8f, false},
    {11, 39.9f, true},
    {11, 40.0f, true},
    {11, 40.1f, true},
    {11, 40.2f, true},

    // ----- Discrete minutes (face midpoints) -----
    {11, 10.0f, false},
    {11, 30.0f, false},
    {11, 50.0f, true},
};

#define TEST_COUNT (sizeof(test_cases) / sizeof(test_cases[0]))
