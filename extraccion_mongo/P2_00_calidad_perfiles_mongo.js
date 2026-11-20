/* =====================================================================
   PARTE 1 · Exploración y problemas de calidad de perfiles_marketing
   Persona 2 · Base marketing_bi (MongoDB)

   Cómo ejecutarlo:
     - En Compass: pestaña _MONGOSH (abajo), pegar cada bloque y Enter.
     - En terminal:  mongosh marketing_bi P2_00_calidad_perfiles_mongo.js
   Cada consulta evidencia un problema. Tomar una captura de cada resultado.
   ===================================================================== */
db = db.getSiblingDB("marketing_bi");

print("\n== 0. Conteo de la colección (esperado: 5206) ==");
printjson(db.perfiles_marketing.countDocuments());

print("\n== P1 (T10). clienteId guardado como texto en vez de número ==");
printjson(db.perfiles_marketing.aggregate([
  { $group: { _id: { $type: "$clienteId" }, documentos: { $sum: 1 } } }
]).toArray());
printjson(db.perfiles_marketing.find({ clienteId: { $type: "string" } },
  { _id: 0, clienteId: 1 }).limit(5).toArray());

print("\n== P2 (T11). Clientes con más de un perfil (duplicados) ==");
printjson(db.perfiles_marketing.aggregate([
  { $group: { _id: { $toInt: "$clienteId" }, perfiles: { $sum: 1 },
              fechas: { $push: "$fechaActualizacion" } } },
  { $match: { perfiles: { $gt: 1 } } },
  { $facet: { total: [{ $count: "clientesDuplicados" }],
              ejemplo: [{ $sort: { _id: 1 } }, { $limit: 3 }] } }
]).toArray());

print("\n== P3 (T12). Intereses escritos de muchas formas (mayúsculas, tildes, espacios, singular) ==");
printjson(db.perfiles_marketing.aggregate([
  { $unwind: "$intereses" },
  { $group: { _id: "$intereses", veces: { $sum: 1 } } },
  { $sort: { _id: 1 } }
]).toArray());

print("\n== P4 (T13). Perfiles sin el objeto fidelizacion ==");
printjson(db.perfiles_marketing.countDocuments({ fidelizacion: { $exists: false } }));

print("\n== P5 (T13). Puntos de fidelización guardados como texto ==");
printjson(db.perfiles_marketing.aggregate([
  { $match: { fidelizacion: { $exists: true } } },
  { $group: { _id: { $type: "$fidelizacion.puntos" }, documentos: { $sum: 1 } } }
]).toArray());

print("\n== P6 (T14). encuestasNPS es un arreglo anidado y no siempre existe ==");
printjson(db.perfiles_marketing.aggregate([
  { $project: { nEncuestas: { $size: { $ifNull: ["$encuestasNPS", []] } } } },
  { $group: { _id: "$nEncuestas", perfiles: { $sum: 1 } } },
  { $sort: { _id: 1 } }
]).toArray());

print("\n== P7 (adicional). Canal preferido sin consentimiento para ese canal (Ley 1581) ==");
printjson(db.perfiles_marketing.aggregate([
  { $match: { canalPreferido: { $ne: "ninguno" } } },
  { $project: { canalPreferido: 1,
      tieneConsentimiento: { $switch: { branches: [
        { case: { $eq: ["$canalPreferido", "email"] },    then: "$consentimientos.email" },
        { case: { $eq: ["$canalPreferido", "sms"] },      then: "$consentimientos.sms" },
        { case: { $eq: ["$canalPreferido", "whatsapp"] }, then: "$consentimientos.whatsapp" } ] } } } },
  { $match: { tieneConsentimiento: false } },
  { $group: { _id: "$canalPreferido", perfiles: { $sum: 1 } } }
]).toArray());
