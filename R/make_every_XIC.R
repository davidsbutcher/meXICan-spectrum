#' make_every_XIC
#'
#' @param rawFileDir
#' @param rawFileName
#' @param targetSeqData
#' @param outputDir
#' @param target_col_name
#' @param target_sequence_col_name
#' @param PTMname_col_name
#' @param PTMformula_col_name1
#' @param PTMformula_col_name2
#' @param use_depleted_isotopes
#' @param sample_n_pforms
#' @param mass_range
#' @param target_charges
#' @param mz_range
#' @param XIC_tol
#' @param use_IAA
#' @param save_output
#' @param abund_cutoff
#'
#' @return
#' @export
#'
#' @importFrom magrittr %>%
#' @importFrom purrr reduce
#'
#' @examples

make_every_XIC <-
   function(
      rawFileDir = NULL,
      rawFileName = NULL,
      targetSeqData = NULL,
      outputDir = getwd(),
      target_col_name = c("UNIPROTKB"),
      target_sequence_col_name = c("ProteoformSequence"),
      PTMname_col_name = c("PTMname"),
      PTMformula_col_name1 = c("FormulaToAdd"),
      PTMformula_col_name2 = c("FormulaToSubtract"),
      use_depleted_isotopes = FALSE,
      sample_n_pforms = NULL,
      mass_range = c(0,100000),
      target_charges = c(1:50),
      mz_range = c(600,2000),
      XIC_tol = 2,
      use_IAA = FALSE,
      save_output = TRUE,
      abund_cutoff = 5
   ) {

      # library(purrr)
      # library(magrittr)
      library(rawDiag)

      # Assertions --------------------------------------------------------------

      assertthat::assert_that(
         assertthat::is.dir(rawFileDir),
         msg = "rawFileDir is not a recognized path"
      )


      assertthat::assert_that(
         assertthat::is.string(rawFileName),
         msg = "rawFileName is not a string"
      )

      assertthat::assert_that(
         assertthat::has_extension(targetSeqData, "csv") |
            is.data.frame(targetSeqData),
         msg = "targetSeqData is not a CSV file or dataframe"
      )

      if (
         assertthat::see_if(assertthat::has_extension(targetSeqData, "csv"))
         == TRUE
      ) {

         assertthat::assert_that(
            assertthat::is.readable(targetSeqData),
            msg = "targetSeqData is not a readable file"
         )

      }

      assertthat::assert_that(
         assertthat::is.dir(outputDir),
         msg = "outputDir is not a recognized directory"
      )

      assertthat::assert_that(
         assertthat::is.flag(use_depleted_isotopes),
         msg = "use_depleted_isotopes should be TRUE or FALSE"
      )

      assertthat::assert_that(
         assertthat::is.flag(use_IAA),
         msg = "use_IAA should be TRUE or FALSE"
      )

      assertthat::assert_that(
         assertthat::is.flag(save_output),
         msg = "save_output should be TRUE or FALSE"
      )

      if (is.null(sample_n_pforms) == FALSE && sample_n_pforms > 0) {

         assertthat::assert_that(
            assertthat::is.count(sample_n_pforms),
            msg = "sample_n_pforms should be a positive integer"
         )

      }

      # Create necessary quosures -----------------------------------------------

      target_col_name <- rlang::enquo(target_col_name)
      target_sequence_col_name_sym <- rlang::sym(target_sequence_col_name)
      target_sequence_col_name <- rlang::enquo(target_sequence_col_name)
      PTMformula_col_name1 <- rlang::enquo(PTMformula_col_name1)
      PTMformula_col_name2 <- rlang::enquo(PTMformula_col_name2)
      PTMname_col_name <- rlang::enquo(PTMname_col_name)

      # Check filename and path -------------------------------------------------

      # purrr::as_mapper(purrr::reduce)

      rawFilesInDir <-
         fs::dir_ls(
            rawFileDir,
            recurse = TRUE,
            type = "file",
            regexp = c("[.]raw$")
         )

      if (length(rawFilesInDir) == 0) {
         stop("No .raw files found in raw file directory")
      }

      if (rawFilesInDir %>%
          stringr::str_detect(rawFileName) %>%
          any() == FALSE) {
         stop("Input raw file not found in raw file directory")
      }

      rawFile <-
         rawFilesInDir %>%
         stringr::str_subset(rawFileName)

      # Make timer ------------------------------------------------------

      timer <-
         timeR::createTimer(verbose = FALSE)

      # ggplot themes -----------------------------------------------------------

      XICtheme <-
         list(
            ggplot2::geom_text(
               data = ~dplyr::filter(.x, int_sum == max(int_sum)),
               ggplot2::aes(
                  x = times,
                  y = int_sum,
                  label = glue::glue(
                     "Max TIC: {format(int_sum, scientific = TRUE, nsmall = 4, digits = 4)}\n RT@Max: {format(times, scientific = FALSE, nsmall = 4, digits = 3)}\n PTM:{!!PTMname}"),
                  alpha = 0.5,
                  size = 3
               ),
               vjust="inward",
               hjust="inward",
               nudge_x = 5
            ),
            ggthemes::theme_clean(base_size = 10),
            # theme(
            #   text = element_text(size = 6),
            #   title = element_text(size = 8),
            #   axis.text = element_text(size = 8),
            #   axis.title = element_text(size = 8)
            # ),
            ggplot2::labs(
               x = "Retention Time (min)",
               y = "Total Ion Current"
            ),
            ggplot2::guides(
               alpha = "none",
               size = "none"
            )
         )


      # Make future workers -----------------------------------------------------

      # timer$start("Make future workers, XIC")
      #
      # future::plan("future::multisession", workers = future_workers)
      #
      # timer$stop("Make future workers, XIC")

      # Load isotopes table -----------------------------------------------------

      if (use_depleted_isotopes == FALSE) {

         # data(isotopes, package = "enviPat")
         #
         # isotopes_to_use <- isotopes

         isotopes_to_use <-
            readr::read_csv(
               system.file(
                  "input",
                  "normal_isotopes.csv",
                  package = "GEX"
               )
            ) %>%
            as.data.frame()

      } else {

         isotopes_to_use <-
            readr::read_csv(
               system.file(
                  "input",
                  "depleted_isotopes.csv",
                  package = "GEX"
               )
            ) %>%
            as.data.frame()

      }


      # Process target sequences ------------------------------------------------

      target_seqs_df <-
         targetSeqData %>%
         {if (!is.data.frame(.)) readr::read_csv(.) else .} %>%
         dplyr::mutate(
            MonoisoMass =
               Peptides::mw(!!target_sequence_col_name_sym, monoisotopic = TRUE)
         ) %>%
         dplyr::filter(
            MonoisoMass >= mass_range[[1]],
            MonoisoMass <= mass_range[[2]]
         ) %>%
         {if (!is.null(sample_n_pforms)) dplyr::sample_n(., size = sample_n_pforms) else .}

      target_seqs <-
         target_seqs_df %>%
         dplyr::select(
            !!target_col_name, !!target_sequence_col_name
         ) %>%
         tibble::deframe() %>%
         as.list()

      # Get elemental composition -----------------------------------------------

      timer$start("Chemical formulas and isotopic distributions")

      chemform_temp <-
         purrr::map(
            target_seqs,
            OrgMassSpecR::ConvertPeptide,
            IAA = use_IAA
         )

      chemform_names <-
         chemform_temp %>%
         purrr::map(unlist) %>%
         purrr::map(names)

      chemform <-
         chemform_temp %>%
         purrr::map(unlist) %>%
         purrr::map2(
            chemform_names,
            ~purrr::map2_chr(.y, .x, paste0)
         ) %>%
         purrr::map(
            paste0,
            collapse = ""
         )

      ## Extract PTM names and make list for later use

      PTM_names_list <-
         target_seqs_df %>%
         dplyr::select(!!target_col_name, !!PTMname_col_name) %>%
         tibble::deframe() %>%
         as.list()

      PTM_names_list[is.na(PTM_names_list) == TRUE] <- "None"

      ## Make list of PTM formulas to ADD

      PTM_form_to_add <-
         target_seqs_df %>%
         dplyr::pull(!!PTMformula_col_name1) %>%
         as.list()

      PTM_form_to_add[is.na(PTM_form_to_add) == TRUE] <- "C0"

      PTM_form_to_add <-
         purrr::map(
            PTM_form_to_add,
            ~enviPat::check_chemform(isotopes = isotopes_to_use, chemforms = .x) %>%
               dplyr::pull(new_formula)
         )

      ## Make list of PTM formulas to SUBTRACT

      PTM_form_to_sub <-
         target_seqs_df %>%
         dplyr::pull(!!PTMformula_col_name2) %>%
         as.list()

      PTM_form_to_sub[is.na(PTM_form_to_sub) == TRUE] <- "C0"

      PTM_form_to_sub <-
         purrr::map(
            PTM_form_to_sub,
            ~enviPat::check_chemform(isotopes = isotopes_to_use, chemforms = .x) %>%
               dplyr::pull(new_formula)
         )

      ## Add and subtract PTM formulas as needed

      chemform <-
         purrr::map2(
            chemform,
            PTM_form_to_add,
            ~enviPat::mergeform(.x, .y)
         ) %>%
         purrr::map2(
            PTM_form_to_sub,
            ~enviPat::subform(.x, .y)
         )

      # Add one H per positive charge

      H_to_merge <-
         target_charges %>%
         purrr::map_chr(~paste0("H", .x)) %>%
         list() %>%
         rep(length(target_seqs))

      chemform_to_merge <-
         chemform %>%
         purrr::map(
            ~rep(.x, length(target_charges))
         )

      chemform_withH <-
         purrr::map2(
            chemform_to_merge,
            H_to_merge,
            ~purrr::map2_chr(.x, .y, ~enviPat::mergeform(.x, .y))
         )

      for (i in seq_along(chemform_withH)) {

         if (
            any(stringr::str_detect(chemform_withH[[i]], "C0|H0|N0|O0|P0|S0")) == TRUE
         ) {

            chemform_withH[[i]] <-
               stringr::str_remove_all(chemform_withH[[i]], "C0|H0|N0|O0|P0|S0")

         }

      }

      rm(chemform_temp)
      rm(chemform_names)
      rm(chemform_to_merge)
      rm(H_to_merge)

      # Calculate isotopic dist -------------------------------------------------

      purrr::map(
         chemform,
         ~enviPat::check_chemform(isotopes = isotopes_to_use, chemforms = .x) %>%
            dplyr::pull(warning) %>%
            any() %>%
            `if`(., stop("Problem with chemical formula"))
      )

      iso_dist <-
         purrr::map2(
            chemform_withH,
            list(target_charges) %>% rep(length(target_seqs)),
            ~purrr::map2(
               .x,
               .y,
               ~enviPat::isopattern(
                  isotopes_to_use,
                  chemform=.x,
                  threshold=0.1,
                  plotit=FALSE,
                  charge=.y,
                  emass=0.00054858,
                  algo=1
               ) %>%
                  purrr::modify_depth(1, tibble::as_tibble) %>%
                  purrr::map(
                     ~dplyr::filter(
                        .x,
                        `m/z` >= mz_range[[1]],
                        `m/z` <= mz_range[[2]],
                        abundance > abund_cutoff
                     )
                  )
            )
         )

      target_charges_list <-
         list(target_charges) %>%
         rep(length(target_seqs))

      iso_dist_list_union <-
         iso_dist %>%
         purrr::modify_depth(3, tibble::as_tibble) %>%
         purrr::map2(
            .y = target_charges_list,
            ~purrr::map2(
               .x = .x,
               .y = .y,
               ~purrr::map2(
                  .x = .x,
                  .y = .y,
                  ~dplyr::mutate(.x, charge = .y) %>%
                     dplyr::filter(
                        `m/z` > mz_range[[1]] & `m/z` < mz_range[[2]]
                     )
               )
            )
         )

      # rm(iso_dist)

      # Keep the next three chunks separate, doesn't work if they are condensed

      iso_dist_list_union <-
         purrr::map(
            iso_dist_list_union,
            purrr::reduce,
            dplyr::union_all
         )

      # Save this for later use in making spectra

      iso_dist_vlines <-
         iso_dist_list_union

      iso_dist_list_union <-
         purrr::map(
            iso_dist_list_union,
            purrr::reduce,
            dplyr::union_all
         ) %>%
         purrr::map(
            ~dplyr::group_by(
               .x,
               `m/z_group` =
                  cut(`m/z`, breaks = seq(mz_range[[1]], mz_range[[2]], by = 0.01))
            ) %>%
               dplyr::arrange(
                  dplyr::desc(abundance), .by_group = TRUE
               ) %>%
               dplyr::slice_head() %>%
               dplyr::ungroup() %>%
               dplyr::select(-`m/z_group`)
         )

      timer$stop("Chemical formulas and isotopic distributions")

      # Calculate XIC -----------------------------------------------------------

      timer$start("Calculate and plot XICs")

      XIC_target_mz <-
         iso_dist_list_union %>%
         purrr::map(~dplyr::pull(.x, `m/z`)) %>%
         purrr::map(unique)

      XIC <-
         purrr::map(
            XIC_target_mz,
            ~rawDiag::readXICs(
               rawfile = rawFile,
               masses = .x,
               tol = XIC_tol
            )
         )

      XIC_nonull <-
         XIC %>%
         purrr::map(kickoutXIC)

      # SAVE SPACE BY DELETING XICS!

      rm(XIC)

      sumXIC1 <-
         XIC_nonull %>%
         purrr::modify_depth(2, tibble::as_tibble) %>%
         purrr::modify_depth(2, ~dplyr::select(.x, times, intensities)) %>%
         purrr::map(purrr::reduce, dplyr::full_join)

      sumXIC2 <-
         sumXIC1 %>%
         purrr::map(~dplyr::group_by(.x, times)) %>%
         purrr::map(~dplyr::summarize(.x, int_sum = sum(intensities)))

      # Get RT corresponding to maximum TIC for each sequence for later use in
      # making spectra

      RT_of_maxTIC <-
         sumXIC2 %>%
         purrr::map(
            ~dplyr::filter(.x, int_sum == max(int_sum))
         ) %>%
         purrr::map(
            ~dplyr::pull(.x, times)
         )

      rawFileMetadata <-
         rawDiag::read.raw(
            rawFile,
            rawDiag = FALSE
         ) %>%
         tibble::as_tibble()

      scanNumber_and_RT <-
         rawFileMetadata %>%
         dplyr::select(scanNumber, StartTime)


      scanNumsToRead <-
         purrr::map(
            RT_of_maxTIC,
            ~dplyr::filter(scanNumber_and_RT, StartTime == .x)
         ) %>%
         purrr::map(
            ~dplyr::pull(.x, scanNumber)
         )

      # Make summary of XIC data

      sumXIC_summary <-
         sumXIC2 %>%
         rlang::set_names(chemform) %>%
         purrr::map(
            ~dplyr::summarize(.x, max_TIC = max(int_sum))
         ) %>%
         purrr::map2(
            names(.),
            ~dplyr::mutate(.x, chem_form = .y)
         ) %>%
         purrr::reduce(dplyr::union_all) %>%
         dplyr::mutate(Sequence = unlist(target_seqs)) %>%
         dplyr::mutate(seq_name = names(target_seqs)) %>%
         dplyr::mutate(RT_of_maxTIC = unlist(RT_of_maxTIC)) %>%
         dplyr::mutate(scan_of_maxTIC = unlist(scanNumsToRead)) %>%
         dplyr::select(seq_name, Sequence, chem_form, max_TIC, tidyr::everything()) %>%
         dplyr::arrange(dplyr::desc(max_TIC))

      # Arrange XICs to go in order of decreasing intensity

      sumXIC2 <-
         sumXIC2 %>%
         .[sumXIC_summary %>% dplyr::pull(seq_name)]


      PTM_names_list <-
         PTM_names_list %>%
         .[sumXIC_summary %>% dplyr::pull(seq_name)]

      iso_dist_list_union <-
         iso_dist_list_union %>%
         .[sumXIC_summary %>% dplyr::pull(seq_name)]

      scanNumsToRead <-
         scanNumsToRead %>%
         .[sumXIC_summary %>% dplyr::pull(seq_name)]

      # Plot XICs ---------------------------------------------------------------

      XIC_plots <-
         purrr::pmap(
            list(
               sumXIC2,
               PTM_names_list,
               names(sumXIC2)
            ),
            ~make_XIC_plot(
               ..1,
               times,
               int_sum,
               ..2,
               ..3
            )
         )

      ########## EVERYTHING AFTER THIS IS CONTROLLED BY save_output!

      if (save_output == TRUE) {

         # MultiArrange XIC grobs -------------------------------------------------------

         XIC_groblist <-
            gridExtra::marrangeGrob(
               grobs = XIC_plots,
               ncol = 5,
               nrow = 3,
               top = rawFileName
            )

         timer$stop("Calculate and plot XICs")

         # Create save directory ---------------------------------------------------

         systime <- format(Sys.time(), "%Y%m%d")

         if (use_depleted_isotopes == FALSE) {

            saveDir <-
               paste0(
                  outputDir,
                  "/",
                  fs::path_ext_remove(rawFileName),
                  "_",
                  length(target_seqs),
                  "seqs_Normiso/"
               ) %>%
               stringr::str_trunc(246, "right", ellipsis = "")

         } else if (use_depleted_isotopes == TRUE) {

            saveDir <-
               paste0(
                  outputDir,
                  "/",
                  fs::path_ext_remove(rawFileName),
                  "_",
                  length(target_seqs),
                  "seqs_IDiso/"
               ) %>%
               stringr::str_trunc(246, "right", ellipsis = "")

         } else {

            stop("use_depleted_isotopes not set to TRUE or FALSE")

         }

         if (dir.exists(saveDir) == FALSE) dir.create(saveDir)

         # Save XIC results --------------------------------------------------------

         timer$start("Save XIC results")

         # Save spreadsheet data

         message(
            paste0(
               "Saving target sequences to ",
               saveDir,
               fs::path_ext_remove(
                  stringr::str_trunc(
                     rawFileName, 90, "right", ellipsis = ""
                  )
               ),
               '_seqs.csv'
            )
         )

         readr::write_csv(
            target_seqs_df,
            path =
               paste0(
                  saveDir,
                  fs::path_ext_remove(
                     stringr::str_trunc(
                        rawFileName, 90, "right", ellipsis = ""
                     )
                  ),
                  '_seqs.csv'
               )
         )

         # writexl::write_xlsx(
         #    target_seqs_df,
         #    path =
         #       paste0(
         #          saveDir,
         #          fs::path_ext_remove(
         #             stringr::str_trunc(
         #                rawFileName, 90, "right", ellipsis = ""
         #             )
         #          ),
         #          '_target_seqs.xlsx'
         #       )
         # )

         readr::write_csv(
            sumXIC_summary,
            path =
               paste0(
                  saveDir,
                  fs::path_ext_remove(
                     stringr::str_trunc(
                        rawFileName, 90, "right", ellipsis = ""
                     )
                  ),
                  '_XICsum.csv'
               )
         )

         purrr::imap(
            iso_dist_list_union,
            ~dplyr::mutate(.x, accession = .y)
         ) %>%
            purrr::reduce(dplyr::union_all) %>%
            dplyr::select(accession, tidyr::everything()) %>%
            readr::write_csv(
               path =
                  paste0(
                     saveDir,
                     fs::path_ext_remove(
                        stringr::str_trunc(
                           rawFileName, 90, "right", ellipsis = ""
                        )
                     ),
                     '_isodist.csv'
                  )
            )

         # Save chromatograms, all together

         XIC_groblist_filename <-
            paste0(
               saveDir,
               fs::path_ext_remove(rawFileName),
               "_XICs"
            )

         ggplot2::ggsave(
            filename = paste0(XIC_groblist_filename, ".pdf"),
            plot = XIC_groblist,
            width = 20,
            height = 12,
         )

         timer$stop("Save XIC results")

      }

      return(
         list(
            scanNumsToRead,
            iso_dist_list_union,
            timer,
            rawFile,
            rawFileMetadata,
            saveDir,
            rawFileName,
            target_seqs,
            sample_n_pforms,
            PTM_names_list,
            sumXIC_summary,
            iso_dist_vlines,
            XIC_plots
         )
      )
   }
