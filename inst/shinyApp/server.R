library(shiny)
library(shinydashboard)
library(dplyr)
library(ggplot2)
library(plotly)
library(purrr)
library(ewavesPDFshiny)
library(DT)
library(tidyr)

shiny_server <- function(input, output, session) {

    dataview_dataframe <- tibble(
        AT = numeric(0),
        DT = numeric(0),
        Epeak = numeric(0),
        K = numeric(0),
        C = numeric(0),
        x0 = numeric(0),
        Tau = numeric(0),
        KFEI = numeric(0),
        VTI = numeric(0),
        peak_driving_force = numeric(0),
        peak_resistive_force = numeric(0),
        damping_index = numeric(0),
        filling_energy = numeric(0),
        M = numeric(0),
        B = numeric(0),
        R2 = numeric(0),
        adj_R2 = numeric(0),
        velocity_curve = vector("list", 0)
    )

    col_names <- c(
        "AT"="E\nAcceleration\nTime\n[ms]",
        "DT"="E\nDecceleration\nTime\n[ms]",
        "Epeak"="E\nVmax\n[m/s]",
        "K"="Stiffness\n(k)\n[g/s2]",
        "C"="Viscoelasticity\n(c)\n[g/s]",
        "x0"="Load\n(x0)\n[cm]",
        "Tau"="Tau\n[ms]",
        "KFEI"="KFEI\n[%]",
        "VTI"="VTI\n[cm]",
        "peak_driving_force"="Peak\nDriving\nForce\n[mN]",
        "peak_resistive_force"="Peak\nResistive\nForce\n[mN]",
        "damping_index"="Damping\nIndex\n[g2/s2]",
        "filling_energy"="Filling\nEnergy\n[mJ]",
        "M" = "M [mN]",
        "B" = "B",
        "R2" = "R\U00B2",
        "adj_R2" = "adj R\U00B2"
    )
    # Setup reactive components -------------------------------------------------

    dataview_values <- reactiveValues(data = dataview_dataframe)
    summary_values <- reactiveValues(data = dataview_dataframe %>% select(-velocity_curve))
    .startup_message <- ""
    message_values <- reactiveValues(text = .startup_message)
    # Main functions -----------------------------------------------------------

    observeEvent(input$enter, {
        ## Requisites ---------------------------------------------------------------

        # when pressing enter (13)
        if (input$enter == 13 || ((input$enter == 9) & (input$epeak_focus))) {
            TRUE
        } else {
            return()
        }
        # require entries in AT, DT, Epeak
        req(input$at_input)
        req(input$dt_input)
        req(input$epeak_input)

        ## Generate PDF variables -------------------------------------------------

        if ((input$at_input > 500) ||
            (input$at_input < 10) ||
            (input$dt_input > 500) ||
            (input$dt_input < 10) ||
            (input$epeak_input > 5) ||
            (input$epeak_input < 0.1)) {

            .text <- "Error: Unphysiological results"
            message_values$text <- .text
            session$sendCustomMessage(type = "refocus", message = list(NULL))

        } else {

            message_values$text <- .startup_message
            # get the input variables
            input_AT <- input$at_input
            input_DT <- input$dt_input
            input_Epeak <- input$epeak_input

            initial_pdf_parameters <- generate_c_k_x0(AT = input_AT,
                                                      DT = input_DT,
                                                      Epeak = input_Epeak)

            secondary_pdf_parameters <- generate_pdf_parameters(C     = initial_pdf_parameters$C,
                                                                K     = initial_pdf_parameters$K,
                                                                x0    = initial_pdf_parameters$x0,
                                                                AT    = input_AT,
                                                                DT    = input_DT,
                                                                Epeak = input_Epeak)
            ## Perform checks ---------------------------------------------------------
            # check for unphysiological results
            if (initial_pdf_parameters$C < 0) {
                .text <- "Error: Unphysiological results"
                message_values$text <- .text
                session$sendCustomMessage(type = "refocus", message = list(NULL))
            } else {
                message_values$text <- .startup_message


                ## Data for plots ---------------------------------------------------------
                curve_parameters <- list(K = initial_pdf_parameters$K,
                                         C = initial_pdf_parameters$C,
                                         x0 = initial_pdf_parameters$x0)
                # generate data for each curve from parameters
                velocity_curve <- purrr::pmap(
                    curve_parameters,
                    ewave_velocity_fx_time_data
                )

                ## Prepare data for presentation -------------------------------------------
                pdf_data <- tibble(
                    AT = input_AT,
                    DT = input_DT,
                    Epeak = input_Epeak,
                    K = initial_pdf_parameters$K,
                    C = initial_pdf_parameters$C,
                    x0 = abs(initial_pdf_parameters$x0) * 100,             #  Convert from meter to cm, present as absolut value
                    Tau = (secondary_pdf_parameters$Tau) * 1000,            #  Convert from seconds to milliseconds
                    KFEI = secondary_pdf_parameters$KFEI,
                    VTI = secondary_pdf_parameters$VTI * 100,               # Convert from meter to cm
                    peak_driving_force = abs(secondary_pdf_parameters$peak_driving_force), #  Present as absolute value
                    peak_resistive_force = secondary_pdf_parameters$peak_resistive_force,
                    damping_index = secondary_pdf_parameters$damping_index,
                    filling_energy = secondary_pdf_parameters$filling_energy,
                    M = NA,
                    B = NA,
                    R2 = NA,
                    adj_R2 = NA,
                    velocity_curve = velocity_curve
                )

                # Combine previous and newly added data
                dataview_values$data <- rbind(dataview_values$data, pdf_data)

                lm_fit <- lm(peak_driving_force ~ peak_resistive_force,
                             data = dataview_values$data)

                lm_data <- data.frame(
                    # Intercept
                    M = coef(lm_fit)[1],
                    # beta
                    B = coef(lm_fit)[2],
                    R2 = summary(lm_fit)$r.squared,
                    adj_R2 = summary(lm_fit)$adj.r.squared
                )

                mean_values  <- dataview_values$data %>%
                    select(-velocity_curve) %>%
                    summarize_all(mean)

                sd_values    <- dataview_values$data %>%
                    select(-velocity_curve) %>%
                    summarize_all(sd)

                mean_values$M <- coef(lm_fit)[1] # Intercept
                mean_values$B <- coef(lm_fit)[2] # Beta
                mean_values$R2 <- summary(lm_fit)$r.squared
                mean_values$adj_R2 <- summary(lm_fit)$adj.r.squared

                summary_values$data <- rbind(mean_values, sd_values)
                row.names(summary_values$data) <- c("mean", "sd")


                ## Return focus to first input --------------------------------------------
                session$sendCustomMessage(type ="refocus",message = list(NULL))

                updateNumericInput(session, "at_input", value = NA)
                updateNumericInput(session, "dt_input", value = NA)
                updateNumericInput(session, "epeak_input", value = NA)
            }
        }

    }
    )

    # On delete function ----------------------------------------------------------

    observeEvent(input$delete, {
        dataview_values$data <- dataview_values$data[-input$dataview_rows_selected, ]

        if(nrow(dataview_values$data)){

            lm_fit <- lm(peak_driving_force ~ peak_resistive_force,
                         data = dataview_values$data)

            lm_data <- data.frame(
                # Intercept
                M = coef(lm_fit)[1],
                # beta
                B = coef(lm_fit)[2],
                R2 = summary(lm_fit)$r.squared,
                adj_R2 = summary(lm_fit)$adj.r.squared
            )

            mean_values  <- dataview_values$data %>%
                select(-velocity_curve) %>%
                summarize_all(mean)

            sd_values    <- dataview_values$data %>%
                select(-velocity_curve) %>%
                summarize_all(sd)

            mean_values$M <- coef(lm_fit)[1] # Intercept
            mean_values$B <- coef(lm_fit)[2] # Beta
            mean_values$R2 <- summary(lm_fit)$r.squared
            mean_values$adj_R2 <- summary(lm_fit)$adj.r.squared

            summary_values$data <- rbind(mean_values, sd_values)
            row.names(summary_values$data) <- c("mean", "sd")
            session$sendCustomMessage(type = "refocus", message = list(NULL))


            updateNumericInput(session, "at_input", value = NA)
            updateNumericInput(session, "dt_input", value = NA)
            updateNumericInput(session, "epeak_input", value = NA)
        } else {
            summary_values$data <- dataview_values$data
            session$sendCustomMessage(type = "refocus", message = list(NULL))


            updateNumericInput(session, "at_input", value = NA)
            updateNumericInput(session, "dt_input", value = NA)
            updateNumericInput(session, "epeak_input", value = NA)
        }
    })

    # Rendering ------------------------------------------------------------------
    output$messages <- renderText({message_values$text})

    output$dataview <- DT::renderDataTable({
        DT::datatable(rbind(data.frame(dataview_values$data %>% select(-velocity_curve)),
                            summary_values$data),
                      colnames=c(
                          "E\nAcceleration\nTime\n[ms]"="AT",
                          "E\nDecceleration\nTime\n[ms]"="DT",
                          "E\nVmax\n[m/s]"="Epeak",
                          "Stiffness\n(k)\n[g/s2]"="K",
                          "Viscoelasticity\n(c)\n[g/s]"="C",
                          "Load\n(x0)\n[cm]"="x0",
                          "Tau\n[ms]"="Tau",
                          "KFEI\n[%]"="KFEI",
                          "VTI\n[cm]"="VTI",
                          "Peak\nDriving\nForce\n[mN]"="peak_driving_force",
                          "Peak\nResistive\nForce\n[mN]"="peak_resistive_force",
                          "Damping\nIndex\n[g2/s2]"="damping_index",
                          "Filling\nEnergy\n[mJ]"="filling_energy",
                          "M [mN]" = "M",
                          "B" = "B",
                          "R\U00B2" = "R2",
                          "adj R\U00B2" = "adj_R2"),
                      extensions = c('Buttons'),
                      options = list(
                          dom = 'Brtip',
                          buttons = c('copy', 'csv', 'excel'),
                          ordering = FALSE
                      ),
                      autoHideNavigation = TRUE,
                      class = "compact"
        ) %>%
            formatRound(col_names[c("AT", "DT", "K", "Tau", "damping_index")], digits=0) %>%
            formatPercentage(col_names["KFEI"], digits=1) %>%
            formatRound(col_names[c("C", "x0", "VTI", "peak_driving_force",
                                    "peak_resistive_force", "M", "B")],
                        digits=1) %>%
            formatRound(col_names[c("Epeak", "filling_energy", "R2", "adj_R2")], digits=2)
    })

    output$scatterplot <- plotly::renderPlotly({
        p_scatterplot <- ggplot(dataview_values$data, aes(x=peak_resistive_force,
                                                          y=peak_driving_force)) +
            geom_point() +
            geom_smooth(method="lm", se=FALSE, show.legend=TRUE) +
            labs(y="Peak Driving Force [mN]",
                 x="Peak Resistive Force [mN]",
                 parse=TRUE) +
            theme_light()

        ggplotly(p_scatterplot)
    })

    output$velocityplot <- plotly::renderPlotly({
        if(!nrow(dataview_values$data)){
            example_data <- ewave_velocity_fx_time_data(41.58, 384.36, -0.1586)
            p_velocityplot <- ggplot(example_data, aes(x=x, y=y)) +
                geom_line() +
                labs(x="Time [s]", y="Velocity [m/s]") +
                annotate("text", x=0.3, y=0.9, label="Example curve", size=10) +
                scale_y_continuous(limits=c(0, 1.2), expand=c(0,0)) +
                scale_x_continuous(limits=c(0, 0.405), expand=c(0,0)) +
                theme_light()
        } else{
            velocity_data <- dataview_values$data %>%
                select(velocity_curve) %>%
                mutate(id = row.names(.)) %>%
                unnest(velocity_curve)

            y_max <- velocity_data %>%
                pull(y) %>%
                max(., na.rm = TRUE)

            p_velocityplot <- ggplot(velocity_data, aes(x=x, y=y, colour=id)) +
                geom_line() +
                labs(x="Time [s]", y="Velocity [m/s]") +
                theme_light() +
                scale_y_continuous(limits = c(0, y_max+0.1), expand = c(0,0)) +
                scale_x_continuous(limits = c(0, 0.405), expand = c(0,0)) +
                guides(colour=guide_legend(title = "ID"))
        }
        ggplotly(p_velocityplot)
    })

    session$allowReconnect(TRUE)
}
