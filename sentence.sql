\

CREATE TABLE projects(
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    tenant_id INT NOT NULL
);


CREATE SCHEMA acme;