-- Doctors collection: one document per doctor (the master copy of doctor data).

SET search_path TO hospital;
SELECT json_build_object('_id', doctor_id, 'first_name', first_name,
                         'last_name', last_name, 'specialty', specialty, 'phone', phone)
FROM doctor ORDER BY doctor_id;