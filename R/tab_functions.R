### tab functions
# Jesse Zlotoff
# 3/4/19


#' Build Collapses
#'
#' Combine values in a given column to create collapsed categories
#'
#' @param df dataframe to edit
#' @param variable string variable/column name to edit
#' @param collapses list of collapses with "label"=c(inputs).  use "@auto" to auto-generate labels.
#' @return collapsed dataframe
#' @export
#'
collapser <- function(df, variable, collapses) {

    require(lazyeval)
    require(dplyr)

    new_levels <- c()
    for(lab in names(collapses)) {
        if(substr(lab,1,5) == "@auto") {
            new_lab <- paste(unlist(collapses[lab]), collapse='/')
        }
        else {
            new_lab <- lab
        }
        new_levels <- c(new_levels, new_lab)

        for(v in unlist(collapses[lab])) {
            m_call <- lazyeval::interp(quote(ifelse(variable==v, new_lab, as.character(variable))),
                                     variable=as.name(variable))
            df <- df %>%
                mutate_(.dots = setNames(list(m_call), variable))
        }
    }

    m_call <- lazyeval::interp(quote(factor(variable, levels=new_levels)),
                               variable=as.name(variable))
    df <- df %>%
        mutate_(.dots = setNames(list(m_call), variable))
    return(df)
}

#' Reorder Tab Columns
#'
#' Reorder dataframe columns to display in logical order for tabs.
#'
#' @param df dataframe to edit
#' @return updated dataframe
#' @export
#'
reorder_columns <- function(df) {

    require(dplyr)

    pcols <- df %>%
        select(-category, -starts_with("n_"), -starts_with("lci_"), -starts_with("uci_")) %>%
        names()

    old <- names(df)
    new <- c("category")
    for (c in pcols) {
        new <- append(new, c)
        if (paste0("lci_",c) %in% old) {new <- append(new, paste0("lci_",c))}
        if (paste0("uci_",c) %in% old) {new <- append(new, paste0("uci_",c))}
        if (paste0("n_",c) %in% old) {new <- append(new, paste0("n_",c))}
    }

    df <- df %>%
        select(new)

    return(df)
}


#' Valid Tab Inputs
#'
#' Check input dataframe and column(s) to tab functions.
#'
#' @param df dataframe to check
#' @param v1 variable name to check
#' @param v2 variable name to check.  DEFAULT "NULL"
#' @return error/warning message, or empty string
#' @export
#'
valid_tab_inputs <- function(df, v1, v2="NULL") {

    if (!is.data.frame(df)) {
        return("first argument is not a dataframe")
    }

    if (!is.element(v1,names(df))) {
        return(paste(v1, "not present in dataframe"))
    }

    if ("vv1" %in% names(df)) {
        return("vv1 already present in dataframe")
    }

    if (v2!="NULL") {
        if (!is.element(v2,names(df))) {
            return(paste(v2, "not present in dataframe"))
        }

        if ("vv2" %in% names(df)) {
            return("vv2 already present in dataframe")
        }
    }

    return("")
}


#' Weighted Tabs
#'
#' Run weighted crosstabs on one or two variables, using quoted inputs.
#'
#' @param df input dataframe
#' @param v1 string name of 1st variable/column to tabulate
#' @param v2 string name of optional 2nd variable/column to tablulate.  DEFAULT "NULL"
#' @param weight_var string name of weight variable/column.  DEFAULT NULL
#' @param sdesign survey package surveydesign object.  DEFAULT NULL
#' @param nsize boolean flag to include n-sizes in output.  DEFAULT FALSE
#' @param ci boolean flag to include lower- and upper- bounds of confidence intervals.  DEFAULT FALSE
#' @param to_factor boolean flag to convert v1/v2 to factors, if needed.  DEFAULT TRUE
#' @return dataframe of tab results
#' @export
wtab <- function(df, v1, v2 = "NULL", weight_var = NULL, sdesign = NULL, nsize = FALSE, ci = FALSE, to_factor=TRUE) {

    require(dplyr)
    require(tibble)
    require(stringr)

    # check input
    msg <- valid_tab_inputs(df, v1, v2)
    if (msg!="") {
        stop(msg)
    }

    # drop NA values of v1 and, if needed, v2
    df <- df %>%
        rename_("vv1" = v1) %>%
        filter(!is.na(vv1))
    if (v2!="NULL") {
        df <- df %>%
            rename_("vv2" = v2) %>%
            filter(!is.na(vv2))
    }

    # check that v1/v2 are factors
    if (!is.factor(df$vv1)) {
        if (to_factor==TRUE) {
            df$vv1 <- as.factor(df$vv1)
        } else {
            stop(v1, ' is not a factor variable.  Set to_factor=TRUE to automatically convert it.')
            geterrmessage()
        }
    }
    if (v2!="NULL") {
        if (!is.factor(df$vv2)) {
            if (to_factor==TRUE) {
                df$vv2 <- as.factor(df$vv2)
            } else {
                stop(v2, ' is not a factor variable.  Set to_factor=TRUE to automatically convert it.')
                geterrmessage()
            }
        }
    }


    if (is.null(sdesign)) { # need to build svy design
        wform <- reformulate(weight_var)
        sdesign <- svydesign(ids = ~0, data = df, weights = wform)
    }

    est <- svymean(~vv1, design = sdesign) %>%
        as.tibble() %>%
        rownames_to_column("category") %>%
        rename(total = mean, se_total = SE)

    if(nsize == TRUE) { # calculate weighted n for total
        wtdn <- svytotal(~vv1, design = sdesign) %>%
            as.tibble() %>%
            rownames_to_column("category") %>%
            rename(n_total = total) %>%
            select(-SE)
        est <- est %>%
            left_join(wtdn, by="category")
        rm(wtdn)
    }

    if(ci == TRUE) { # calculate moe/ci for total
        est <- est %>%
            mutate(moe_total = 1.96 * se_total,
                   lci_total = total - moe_total,
                   uci_total = total + moe_total) %>%
            select(-moe_total, everything())
    }

    est <- est %>%
        select(-se_total)

    # two-way tab
    if(v2!="NULL") {
        est2 <- svyby(~vv1, ~vv2, design = sdesign, FUN = svymean, keep.names = FALSE) %>%
            as.tibble() %>%
            gather(key = category, value = value, -vv2) %>%
            mutate(col = ifelse(grepl("^se\\.", category), paste0("se_", vv2) , paste(vv2)),
                   category = sub("^se\\.(.*)", "\\1", category)
            ) %>%
            select(-vv2) %>%
            spread(key = col, value = "value")

        if(nsize == TRUE) { # calculate weighted n for subgroups
            wtdn <- svyby(~vv1, ~vv2, design = sdesign, FUN = svytotal, keep.names = FALSE) %>%
                as.tibble() %>%
                select(-starts_with("se.")) %>%
                gather(key = category, value = value, -vv2) %>%
                mutate(col = paste0("n_", vv2)) %>%
                select(-vv2) %>%
                spread(key = col, value = "value")

            est2 <- est2 %>%
                left_join(wtdn, by="category")
            rm(wtdn)
        }

        if(ci == TRUE) { # calculate moe/ci for subgroups, via reshaping
            ci <- est2 %>%
                select(-starts_with("n_")) %>%
                gather(key, val, -category) %>%
                separate(key, c("prefix", "col"), fill = "left") %>%
                spread(prefix, val) %>%
                rename(p = `<NA>`)
            ci <- ci %>%
                mutate(moe = 1.96 * se,
                       lci = p - moe,
                       uci = p + moe)
            ci <- ci %>%
                gather(key, val, -c(category, col)) %>%
                unite(col, c(key, col)) %>%
                filter(!grepl("^se_", col),
                       !grepl("^p_", col)) %>%
                spread(col, val)

            est2 <- est2 %>%
                left_join(ci, by="category")
            rm(ci)
        }

        est <- est2 %>%
            full_join(est, by="category")
    }

    est <- est %>%
        mutate(category = str_replace(category, paste0("^vv1", "(.*)"), "\\1")) %>%
        select(-starts_with("se_"),
               -starts_with("moe_")) %>%
        select(-starts_with("n_"),
               -starts_with("lci_"),
               -starts_with("uci_"),
               everything()) %>%
        select(category, total, everything())

    est <- reorder_columns(est)
    return(est)
}


#' Unweighted Tabs
#'
#' Run unweighted crosstabs on one or two variables, using quoted inputs.
#'
#' @param df input dataframe
#' @param v1 string name of 1st variable/column to tabulate
#' @param v2 string name of optional 2nd variable/column to tablulate.  DEFAULT "NULL"
#' @param nsize boolean flag to include n-sizes in output.  DEFAULT FALSE
#' @param ci boolean flag to include lower- and upper- bounds of confidence intervals.  DEFAULT FALSE
#' @return dataframe of tab results
#' @export
utab <- function(df, v1, v2 = "NULL", nsize = FALSE, ci = FALSE) {

    require(dplyr)
    require(tibble)
    require(tidyr)
    require(stringr)

    # check input
    msg <- valid_tab_inputs(df, v1, v2)
    if (msg!="") {
        stop(msg)
    }

    est <- df %>%
        select(one_of(v1)) %>%
        table() %>%
        as.tibble() %>%
        mutate(total = n / sum(n)) %>%
        rename(category = 1, n_total = n) %>%
        select(category, total, n_total)

    if (ci == TRUE) {
        est <- est %>%
            mutate(moe = 1.96 * sqrt((total * (1-total))/n_total),
                   lci_total = total - moe,
                   uci_total = total + moe
            ) %>%
            select(-moe)
    }

    if(v2!="NULL") {
        est2 <- df %>%
            select_(v1, v2) %>%
            table() %>%
            as.tibble() %>%
            spread(key = 2, value = n) %>%
            rename_at(vars(-1), .funs=funs(paste0(., "_n"))) %>%
            mutate_at(vars(-1), .funs=funs(pct = . / sum(.))) %>%
            rename_at(vars(ends_with("_n_pct")), .funs = funs(substr(., 1, str_length(.) -6))) %>%
            rename_at(vars(ends_with("_n")), .funs = funs(sub("^([^_]+)_n", "n_\\1", .))) %>%
            rename(category = 1)

        if (ci == TRUE) {
            ci <- est2 %>%
                gather(key, val, -category) %>%
                separate(key, c("prefix", "col"), fill = "left") %>%
                spread(prefix, val) %>%
                rename(p = `<NA>`)
            ci <- ci %>%
                group_by(col) %>%
                mutate(col_n = sum(n)) %>%
                ungroup() %>%
                mutate(moe = 1.96 * sqrt((p * (1-p))/col_n),
                       lci = p - moe,
                       uci = p + moe) %>%
                select(-col_n, -moe)
            ci <- ci %>%
                gather(key, val, -c(category, col)) %>%
                unite(col, c(key, col)) %>%
                filter(!grepl("^n_", col),
                       !grepl("^p_", col)) %>%
                spread(col, val)

            est2 <- est2 %>%
                left_join(ci, by="category")
            rm(ci)
        }

        est <- est %>%
            full_join(est2, by="category")

    }

    if(nsize == FALSE) {
        est <- est %>%
            select(-starts_with("n_"))
    }

    est <- est %>%
        select(category, total, everything())

    est <- reorder_columns(est)
    return(est)
}


#' Tabs - Quoted Input
#'
#' Run weighted or unweighted crosstabs on one or two variables, using quoted inputs.
#'
#' @param df input dataframe
#' @param v1 string name of 1st variable/column to tabulate
#' @param v2 string name of optional 2nd variable/column to tablulate.  DEFAULT "NULL"
#' @param weight_var string name of weight variable/column.  DEFAULT NULL
#' @param sdesign survey package surveydesign object.  DEFAULT NULL
#' @param nsize boolean flag to include n-sizes in output.  DEFAULT FALSE
#' @param ci boolean flag to include lower- and upper- bounds of confidence intervals.  DEFAULT FALSE
#' @param to_factor boolean flag to convert v1/v2 to factors, if needed.  DEFAULT TRUE
#' @param collapses list of categories to collapse as "new name"=c(inputs) DEFAULT list()
#' @return dataframe of tab results
#' @seealso \code{\link{wtab}}, \code{\link{utab}} which this function wraps
#' @export
stab <- function(df, v1, v2 = "NULL", weight_var = "NULL", sdesign = NULL, nsize = FALSE, ci = FALSE, to_factor=TRUE, collapses=list()) {

    require(survey)

    if (weight_var=="NULL" & is.null(sdesign)) {
        est <- utab(df, v1, v2 = v2, nsize = nsize, ci = ci)
    } else {
        est <- wtab(df, v1, v2 = v2, weight_var = weight_var, sdesign = sdesign, nsize = nsize, ci = ci, to_factor=to_factor)
    }

    if (length(collapses) > 0) {
        cdf <- collapser(df, v1, collapses)
        if (weight_var=="NULL" & is.null(sdesign)) {
            est2 <- utab(cdf, v1, v2 = v2, nsize = nsize, ci = ci)
        } else {
            est2 <- wtab(cdf, v1, v2 = v2, weight_var = weight_var, sdesign = sdesign, nsize = nsize, ci = ci, to_factor=to_factor)
        }

        est <- est %>%
            bind_rows(est2)
    }

    return(est)
}


#' Tabs - Unquoted Input
#'
#' Run weighted or unweighted crosstabs on one or two variables, using unquoted inputs.
#'
#' @param df input dataframe
#' @param v1 name of 1st variable/column to tabulate
#' @param v2 name of optional 2nd variable/column to tablulate.  DEFAULT NULL
#' @param weight_var  name of weight variable/column.  DEFAULT NULL
#' @param sdesign survey package surveydesign object.  DEFAULT NULL
#' @param nsize boolean flag to include n-sizes in output.  DEFAULT FALSE
#' @param ci boolean flag to include lower- and upper- bounds of confidence intervals.  DEFAULT FALSE
#' @param to_factor boolean flag to convert v1/v2 to factors, if needed.  DEFAULT TRUE
#' @param collapses list of categories to collapse as "new name"=c(inputs) DEFAULT list()
#' @return dataframe of tab results
#' @seealso \code{\link{stab}} which this function wraps
#' @export
tab <- function(df, v1, v2 = NULL, weight_var = NULL, sdesign = NULL, nsize = FALSE, ci = FALSE, to_factor=TRUE, collapses=list()) {

    wt_str <- deparse(substitute(weight_var))
    v1_str <- deparse(substitute(v1))
    v2_str <- deparse(substitute(v2))
    paste(c(v1_str, v2_str, wt_str))

    est <- stab(df, v1_str, v2 = v2_str, weight_var = wt_str, sdesign = sdesign, nsize = nsize, ci = ci, to_factor=to_factor, collapses=collapses)

    return(est)
}


#' Clean Up Column Names
#'
#' Convert machine-readable tab column names to human-readable names.
#'
#' @param col_name string column name
#' @return string updated column name
#' @export
pretty_col_name <- function(col_name) {

    s <- strsplit(as.character(col_name), "_")[[1]]
    col_name <- paste(toupper(substring(s, 1,1)), substring(s, 2),
          sep="", collapse=" ")
    return(col_name)
}

