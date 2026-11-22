FROM rocker/shiny:4.4.1

RUN R -e "install.packages(c('shiny','htmltools','jsonlite','base64enc'), repos='https://cloud.r-project.org')"

WORKDIR /srv/shiny-server/titra
COPY app.R ./
COPY R ./R
COPY www ./www

EXPOSE 3838
CMD ["R", "-e", "shiny::runApp('/srv/shiny-server/titra', host='0.0.0.0', port=3838)"]
