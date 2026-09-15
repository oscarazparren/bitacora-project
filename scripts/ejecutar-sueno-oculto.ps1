# Lanzador para el Programador de tareas de Windows.
# Evita que la revisión diaria abra una consola visible cuando el usuario inicia sesión.
& 'C:\Program Files\Git\bin\bash.exe' -lc '~/repos/bitacora-project/scripts/sueno.sh --silencioso'
exit $LASTEXITCODE
