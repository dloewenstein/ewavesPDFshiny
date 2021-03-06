curve_fit <- function (expr, from = NULL, to = NULL, n = 101, add=FALSE,
                       type = "l", xname = "x", xlab = xname, ylab = NULL, log = NULL, 
                       xlim = NULL, ...) {
    sexpr <- substitute(expr)
    if (is.name(sexpr)) {
        expr <- call(as.character(sexpr), as.name(xname))
    }
    else {
        if (!((is.call(sexpr) || is.expression(sexpr)) && xname %in% 
              all.vars(sexpr))) 
            stop(gettextf("'expr' must be a function, or a call or an expression containing '%s'", 
                          xname), domain = NA)
        expr <- sexpr
    }
    if (dev.cur() == 1L && !isFALSE(add)) {
        warning("'add' will be ignored as there is no existing plot")
        add <- FALSE
    }
    addF <- isFALSE(add)
    if (is.null(ylab)) 
        ylab <- deparse(expr)
    if (is.null(from) || is.null(to)) {
        xl <- if (!is.null(xlim)) 
            xlim
        else if (!addF) {
            pu <- par("usr")[1L:2L]
            if (par("xaxs") == "r") 
                pu <- extendrange(pu, f = -1/27)
            if (par("xlog")) 
                10^pu
            else pu
        }
        else c(0, 1)
        if (is.null(from)) 
            from <- xl[1L]
        if (is.null(to)) 
            to <- xl[2L]
    }
    lg <- if (length(log)) 
        log
    else if (!addF && par("xlog")) 
        "x"
    else ""
    if (length(lg) == 0) 
        lg <- ""
    if (grepl("x", lg, fixed = TRUE)) {
        if (from <= 0 || to <= 0) 
            stop("'from' and 'to' must be > 0 with log=\"x\"")
        x <- exp(seq.int(log(from), log(to), length.out = n))
    }
    else x <- seq.int(from, to, length.out = n)
    ll <- list(x = x)
    names(ll) <- xname
    y <- eval(expr, envir = ll, enclos = parent.frame())
    if (length(y) != length(x)) 
        stop("'expr' did not evaluate to an object of length 'n'")
    list(x = x, y = y)
}
