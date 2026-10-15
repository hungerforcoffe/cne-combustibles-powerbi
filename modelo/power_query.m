// ============================================================
// Consultas Power Query (M) del modelo cne_combustibles
// ============================================================

// --- Parámetro: carpeta con los CSV (terminar en \) ---
RutaDatos = "C:\ruta\a\cne-combustibles-powerbi\datos\" meta [IsParameterQuery = true, Type = "Text", IsParameterQueryRequired = true]

// --- Staging (no se carga al modelo) ---
// Tipos con cultura en-US: el CSV usa punto decimal y Windows en español lo leería como miles.
stg_Precios =
let
    Origen = Csv.Document(File.Contents(RutaDatos & "dataset_limpio.csv"), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Encabezados = Table.PromoteHeaders(Origen, [PromoteAllScalars = true]),
    Tipos = Table.TransformColumnTypes(Encabezados, {
        {"codigo_estacion", type text}, {"razon_social", type text}, {"distribuidor", type text},
        {"codigo_comuna", Int64.Type}, {"direccion", type text},
        {"latitud", type number}, {"longitud", type number},
        {"tipo_combustible", type text}, {"nombre_combustible", type text}, {"combustible_base", type text},
        {"precio", type number}, {"fecha_actualizacion", type date},
        {"tipo_atencion", type text}, {"en_mantenimiento", Int64.Type}
    }, "en-US"),
    Limpieza = Table.TransformColumns(Tipos, {{"razon_social", Text.Trim, type text}, {"direccion", Text.Trim, type text}, {"distribuidor", Text.Trim, type text}})
in
    Limpieza

// --- Hecho: un precio por estación y tipo de combustible ---
fact_Precios =
let
    Origen = stg_Precios,
    Columnas = Table.SelectColumns(Origen, {"codigo_estacion", "codigo_comuna", "tipo_combustible", "precio", "fecha_actualizacion"})
in
    Columnas

// --- Dimensión estaciones ---
dim_Estacion =
let
    Origen = stg_Precios,
    Columnas = Table.SelectColumns(Origen, {"codigo_estacion", "distribuidor", "razon_social", "direccion", "latitud", "longitud", "en_mantenimiento"}),
    Unicas = Table.Distinct(Columnas, {"codigo_estacion"}),
    Mantencion = Table.TransformColumns(Unicas, {{"en_mantenimiento", each if _ = 1 then "Sí" else "No", type text}}),
    Etiqueta = Table.AddColumn(Mantencion, "estacion", each [distribuidor] & " · " & [direccion], type text)
in
    Etiqueta

// --- Dimensión combustibles ---
dim_Combustible =
let
    Origen = stg_Precios,
    Columnas = Table.SelectColumns(Origen, {"tipo_combustible", "nombre_combustible", "combustible_base", "tipo_atencion"}),
    Unicas = Table.Distinct(Columnas, {"tipo_combustible"}),
    Orden = Table.AddColumn(Unicas, "orden_base", each if [combustible_base] = "Gasolina 93" then 1 else if [combustible_base] = "Gasolina 95" then 2 else if [combustible_base] = "Gasolina 97" then 3 else 4, Int64.Type)
in
    Orden

// --- Dimensión territorial (346 comunas, regiones ordenadas de norte a sur) ---
dim_Comuna =
let
    Origen = Csv.Document(File.Contents(RutaDatos & "codigo_territorial_cne.csv"), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Encabezados = Table.PromoteHeaders(Origen, [PromoteAllScalars = true]),
    Columnas = Table.SelectColumns(Encabezados, {"cut_region", "cut_provincia", "nombre_provincia_dl2339", "cut_comuna", "nombre_comuna_dl2339"}),
    Nombres = Table.RenameColumns(Columnas, {{"cut_region", "codigo_region"}, {"cut_provincia", "codigo_provincia"}, {"nombre_provincia_dl2339", "provincia"}, {"cut_comuna", "codigo_comuna"}, {"nombre_comuna_dl2339", "comuna"}}),
    Tipos = Table.TransformColumnTypes(Nombres, {{"codigo_region", Int64.Type}, {"codigo_provincia", Int64.Type}, {"provincia", type text}, {"codigo_comuna", Int64.Type}, {"comuna", type text}}),
    Regiones = #table(type table [codigo_region = Int64.Type, region = text, orden_region = Int64.Type], {
        {15, "Arica y Parinacota", 1}, {1, "Tarapacá", 2}, {2, "Antofagasta", 3}, {3, "Atacama", 4},
        {4, "Coquimbo", 5}, {5, "Valparaíso", 6}, {13, "Metropolitana", 7}, {6, "O'Higgins", 8},
        {7, "Maule", 9}, {16, "Ñuble", 10}, {8, "Biobío", 11}, {9, "La Araucanía", 12},
        {14, "Los Ríos", 13}, {10, "Los Lagos", 14}, {11, "Aysén", 15}, {12, "Magallanes", 16}}),
    Union = Table.NestedJoin(Tipos, {"codigo_region"}, Regiones, {"codigo_region"}, "r", JoinKind.LeftOuter),
    Expandir = Table.ExpandTableColumn(Union, "r", {"region", "orden_region"})
in
    Expandir
