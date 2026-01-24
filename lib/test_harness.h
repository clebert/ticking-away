#pragma once

// =================================================================================================
// Minimal Test Harness
// =================================================================================================
// Simple test infrastructure for verifying kernel and geometry extractions.
// Designed to work without stdlib (uses only basic integer operations).
//
// Usage:
//   TEST_BEGIN("test_name")
//   ASSERT_EQ(actual, expected)
//   ASSERT_NEAR(actual, expected, tolerance)
//   TEST_END()
//
// Tests print pass/fail status to stdout (requires stdio.h in test runner).

// -------------------------------------------------------------------------------------------------
// Test State (defined in test runner, not here)
// -------------------------------------------------------------------------------------------------
// Test runners should define:
//   static int test_passed;
//   static int test_failed;
//   static const char* current_test;

// -------------------------------------------------------------------------------------------------
// Test Macros
// -------------------------------------------------------------------------------------------------

#define TEST_BEGIN(name)                                                                           \
  do {                                                                                             \
    current_test = (name);                                                                         \
    int _test_errors = 0;

#define TEST_END()                                                                                 \
  if (_test_errors == 0) {                                                                         \
    test_passed++;                                                                                 \
  } else {                                                                                         \
    test_failed++;                                                                                 \
  }                                                                                                \
  }                                                                                                \
  while (0)

// Integer equality assertion
#define ASSERT_EQ(actual, expected)                                                                \
  do {                                                                                             \
    if ((actual) != (expected)) {                                                                  \
      printf("  FAIL: %s: %s == %d, expected %d\n", current_test, #actual, (int)(actual),          \
             (int)(expected));                                                                     \
      _test_errors++;                                                                              \
    }                                                                                              \
  } while (0)

// Floating-point near-equality assertion
#define ASSERT_NEAR(actual, expected, tolerance)                                                   \
  do {                                                                                             \
    float _a = (actual);                                                                           \
    float _e = (expected);                                                                         \
    float _t = (tolerance);                                                                        \
    float _diff = _a - _e;                                                                         \
    if (_diff < 0)                                                                                 \
      _diff = -_diff;                                                                              \
    if (_diff > _t) {                                                                              \
      printf("  FAIL: %s: %s == %f, expected %f (tolerance %f)\n", current_test, #actual,          \
             (double)_a, (double)_e, (double)_t);                                                  \
      _test_errors++;                                                                              \
    }                                                                                              \
  } while (0)

// Boolean true assertion
#define ASSERT_TRUE(condition)                                                                     \
  do {                                                                                             \
    if (!(condition)) {                                                                            \
      printf("  FAIL: %s: %s is false\n", current_test, #condition);                               \
      _test_errors++;                                                                              \
    }                                                                                              \
  } while (0)

// Boolean false assertion
#define ASSERT_FALSE(condition)                                                                    \
  do {                                                                                             \
    if (condition) {                                                                               \
      printf("  FAIL: %s: %s is true\n", current_test, #condition);                                \
      _test_errors++;                                                                              \
    }                                                                                              \
  } while (0)

// -------------------------------------------------------------------------------------------------
// Test Runner Macros
// -------------------------------------------------------------------------------------------------

#define TEST_RUNNER_BEGIN()                                                                        \
  static int test_passed = 0;                                                                      \
  static int test_failed = 0;                                                                      \
  static const char *current_test = "";

#define TEST_RUNNER_END()                                                                          \
  do {                                                                                             \
    printf("\n%d passed, %d failed\n", test_passed, test_failed);                                  \
    return test_failed > 0 ? 1 : 0;                                                                \
  } while (0)
