
test_that("Works with binary matrix", {

  bm <- bind_rows(
            "gene10" = c(rep(0, 9), rep(1, 1)),
            "gen50" = c(rep(0, 5), rep(1, 5)),
            "gene20" = c(rep(0, 8), rep(1, 2)),
            "gene0" = c(rep(0, 10), rep(1, 0))) %>%
    mutate(sample_id = as.character(1:nrow(.)))

  # 10% -----
  expect_no_error(sub <- bm %>%
    subset_by_frequency())

  expect_equal(setdiff(names(bm), names(sub)), "gene0")

  # 20% ----
  expect_no_error(sub <- bm %>%
                    subset_by_frequency(t = .2))

  expect_equal(setdiff(names(bm), names(sub)), c("gene10", "gene0"))

  # 50% ----
  expect_no_error(sub <- bm %>%
                    subset_by_frequency(t = .5))

  expect_equal(setdiff(names(bm), names(sub)),
               c("gene10", "gene20", "gene0"))

  # 100% ----
  expect_no_error(sub <- bm %>%
                    subset_by_frequency(t = 1))

  expect_equal(names(sub), "sample_id")

  # 0% ----
  expect_no_error(sub <- bm %>%
                    subset_by_frequency(t = 0))

  expect_equal(sort(names(bm)), sort(names(sub)))

 })


test_that("Error when threshold out of bounds", {

  bm <- bind_rows(
    "gene10" = c(rep(0, 9), rep(1, 1)),
    "gen50" = c(rep(0, 5), rep(1, 5)),
    "gene20" = c(rep(0, 8), rep(1, 2)),
    "gene0" = c(rep(0, 10), rep(1, 0))) %>%
    mutate(sample_id = as.character(1:nrow(.)))

  expect_error(sub <- bm %>%
                    subset_by_frequency(t = -1))

  expect_error(sub <- bm %>%
                 subset_by_frequency(t = 2))

})


test_that("Error when missing sample ID", {

  bm <- bind_rows(
    "gene10" = c(rep(0, 9), rep(1, 1)),
    "gen50" = c(rep(0, 5), rep(1, 5)),
    "gene20" = c(rep(0, 8), rep(1, 2)),
    "gene0" = c(rep(0, 10), rep(1, 0)))

  expect_error(sub <- bm %>%
                 subset_by_frequency(t = .5))

})


test_that("Error when non numeric cols", {

  bm <- bind_rows(
    "gene10" = c(rep(0, 9), rep(1, 1)),
    "gen50" = c(rep(0, 5), rep(1, 5)),
    "gene20" = c(rep(0, 8), rep(1, 2)),
    "gene0" = c(rep(0, 10), rep(1, 0))) %>%
    mutate(sample_id = as.character(1:nrow(.)))

  bm <- bm %>%
    mutate(gene10 = as.character(gene10))

  expect_error(sub <- bm %>%
                 subset_by_frequency(t = .5), "gene10$")

})

test_that("Counts NAs correctly", {

  bm <- bind_rows(
    "genenow50" = c(0, 0, 0, 0, 0,0,0,1,1,1),
    "gen50" = c(rep(0, 5), rep(1, 5)),
    "gene20" = c(rep(0, 8), rep(1, 2)),
    "gene0" = c(rep(0, 10), rep(1, 0))) %>%
    mutate(sample_id = as.character(1:nrow(.)))

  bm_na <- bind_rows(
    "genenow50" = c(NA, NA, NA, NA, 0,0,0,1,1,1),
    "gen50" = c(rep(0, 5), rep(1, 5)),
    "gene20" = c(rep(0, 8), rep(1, 2)),
    "gene0" = c(rep(0, 10), rep(1, 0))) %>%
    mutate(sample_id = as.character(1:nrow(.)))

  no_na <- bm %>%
    subset_by_frequency(t = .5)

  na <- bm_na %>%
    subset_by_frequency(t = .5)

  expect_equal(setdiff(names(na), names(no_na)), "genenow50")

})

test_that("Correctly removes cols with all NA", {

  bm <- bind_rows(
    "allna" = c(rep(NA, 10)),
    "gen50" = c(rep(0, 5), rep(1, 5)),
    "gene20" = c(rep(0, 8), rep(1, 2)),
    "gene0" = c(rep(0, 10), rep(1, 0))) %>%
    mutate(sample_id = as.character(1:nrow(.)))

  sub <- bm %>%
    subset_by_frequency(t = 0)

  expect_equal(setdiff(names(bm), names(sub)), "allna")

})

test_that("Other columns are retained in `other_vars`", {

  bm <- bind_rows(
    "gen50" = c(rep(0, 5), rep(1, 5)),
    "gene20" = c(rep(0, 8), rep(1, 2)),
    "gene0" = c(rep(0, 10), rep(1, 0)),
    "sex" = rep(c("F", "M"), 5),
    "stage" = rep(c("I", "II"), 5)) %>%
    mutate(sample_id = as.character(1:nrow(.)))

  sub <- bm %>%
    select(-sex, -stage) %>%
    subset_by_frequency(t = 0)

  sub2 <- bm %>%
    subset_by_frequency(t = 0, other_vars = c(sex, stage))

  expect_equal(setdiff(names(sub2), names(sub)), c("sex", "stage"))


})

test_that("Pass `other_vars` as strings works", {

  bm <- bind_rows(
    "gen50" = c(rep(0, 5), rep(1, 5)),
    "gene20" = c(rep(0, 8), rep(1, 2)),
    "gene0" = c(rep(0, 10), rep(1, 0)),
    "sex" = rep(c("F", "M"), 5),
    "stage" = rep(c("I", "II"), 5)) %>%
    mutate(sample_id = as.character(1:nrow(.)))

  sub <- bm %>%
    subset_by_frequency(t = .1, other_vars = c(sex, stage))

  sub2 <- bm %>%
    subset_by_frequency(t = .1, other_vars = c("sex", "stage"))

  expect_equal(names(sub2), names(sub))
})


test_that("Check for unknown `by` variable", {

  bm <- bind_rows(
    "gen50" = c(rep(0, 5), rep(1, 5)),
    "gene20" = c(rep(0, 8), rep(1, 2)),
    "gene0" = c(rep(0, 10), rep(1, 0)),
    "sex" = rep(c("F", "M"), 5),
    "stage" = rep(c("I", "II"), 5)) %>%
    mutate(sample_id = as.character(1:nrow(.)))

  expect_error(bm |>
                 subset_by_frequency(t = .1, other_vars = c(sex, stage), by = grade),
               "Error in `by=` argument input. Select from")

})


test_that("Check `by` variable works", {

  bm <- bind_rows(
    "gen50" = c(rep(0, 5), rep(1, 5)),
    "gene20" = c(rep(0, 8), rep(1, 2)),
    "gene0" = c(rep(0, 10), rep(1, 0)),
    "sex" = rep(c("F", "M"), 5),
    "stage" = rep(c("I", "II"), 5)) %>%
    mutate(sample_id = as.character(1:nrow(.)))

  sub <- bm %>%
    subset_by_frequency(t = .1, other_vars = stage, by = sex)

  expect_equal(setdiff(names(bm), names(sub)), c("gene0"))

  bm1 <- bind_rows(
    "gen50" = c(rep(0, 5), rep(1, 5)),
    "gene20" = c(rep(0, 8), rep(1, 2)),
    "gene0" = c(rep(0, 10), rep(1, 0)),
    "sex" = c(rep("F", 4), rep("M", 4), "F", "M"),
    "stage" = rep(c("I", "II"), 5)) %>%
    mutate(sample_id = as.character(1:nrow(.)))

  sub1 <- bm1 %>%
    subset_by_frequency(t = .25, other_vars = stage, by = sex)

  sub2 <- bm1 %>%
    subset_by_frequency(t = .85, other_vars = stage, by = sex)

  expect_equal(setdiff(names(bm1), names(sub1)), c("gene20", "gene0"))

  expect_equal(setdiff(names(bm1), names(sub2)), c("gen50", "gene20", "gene0"))
})


test_that("Check categorical `by` variable works", {

  bm <- bind_rows(
    "gen50" = c(rep(0, 5), rep(1, 5)),
    "gene20" = c(rep(0, 8), rep(1, 2)),
    "gene10" = c(rep(0, 9), rep(1, 1)),
    "gene0" = c(rep(0, 10), rep(1, 0)),
    "sex" = c(rep("F", 4), rep("M", 4), "F", "M"),
    "stage" = rep(c("I", "II"), 5),
    "grade" = c(rep(1:4, 2), 1, 2)) %>%
    mutate(sample_id = as.character(1:nrow(.)))

  sub <- subset_by_frequency(bm, other_vars = c("sex", "stage"), by = grade)

  sub1 <- subset_by_frequency(bm, t = 0.35, other_vars = c("sex", "stage"), by = grade)

  expect_equal(setdiff(names(bm), names(sub)), c("gene0"))

  expect_equal(setdiff(names(bm), names(sub1)), c("gene20", "gene10", "gene0"))
})

