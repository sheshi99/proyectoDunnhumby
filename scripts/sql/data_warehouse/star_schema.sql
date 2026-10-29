-- Referencia de diseño; dbt crea las tablas mediante los modelos.
-- No ejecutar este archivo para actualizar una instalacion existente.
-- Cuatro dimensiones y fact_sales en Data_warehouse.public
-- ============================================================
-- PURE STAR SCHEMA (DUNNHUMBY) - POSTGRESQL (ENGLISH)
-- ============================================================

BEGIN;

-- Base de datos destino: Data_warehouse. Esquema: public.

CREATE TABLE IF NOT EXISTS public.dim_promotional_context
(
    promotional_context_id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    has_promotion boolean,
    display_type text,
    mailer_type text,
    household_in_active_campaign boolean,
    active_campaigns_count integer,
    product_associated_with_coupon boolean,
    household_with_redemption_today boolean,
    CONSTRAINT dim_promotional_context_pkey PRIMARY KEY (promotional_context_id)
);

CREATE TABLE IF NOT EXISTS public.dim_household
(
    household_id bigint NOT NULL,
    age_group text,
    marital_status text,
    income_range text,
    homeowner_status text,
    household_composition text,
    household_size text,
    kids_category text,
    CONSTRAINT dim_household_pkey PRIMARY KEY (household_id)
);

CREATE TABLE IF NOT EXISTS public.dim_product
(
    product_id bigint NOT NULL,
    manufacturer bigint,
    department text,
    brand text,
    category text,
    subcategory text,
    product_size text,
    CONSTRAINT dim_product_pkey PRIMARY KEY (product_id)
);

-- Tiempo relativo al dataset: no existe una fecha
CREATE TABLE IF NOT EXISTS public.dim_time
(
    time_id bigint NOT NULL,
    dataset_day_number bigint NOT NULL UNIQUE,
    dataset_week_number bigint NOT NULL,
    CONSTRAINT dim_time_pkey PRIMARY KEY (time_id)
);

CREATE TABLE IF NOT EXISTS public.fact_sales
(
    sale_detail_id bigint NOT NULL GENERATED ALWAYS AS IDENTITY ( INCREMENT 1 START 1 MINVALUE 1 MAXVALUE 9223372036854775807 CACHE 1 ),
    product_id bigint,
    household_id integer,
    time_id integer,
    promotional_context_id bigint NOT NULL,
    store_id integer,
    basket_id bigint,
    transaction_time integer,
    quantity integer,
    -- Sin escala fija: conservar los valores exactos preparados en staging.
    sales_value numeric,
    retail_discount numeric,
    coupon_discount numeric,
    manufacturer_coupon_discount numeric,
    CONSTRAINT fact_sales_pkey PRIMARY KEY (sale_detail_id)
);

-- ============================================================
-- FOREIGN KEY CONSTRAINTS
-- ============================================================

ALTER TABLE IF EXISTS public.fact_sales
    ADD CONSTRAINT fk_sales_promotional_context FOREIGN KEY (promotional_context_id)
    REFERENCES public.dim_promotional_context (promotional_context_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;

ALTER TABLE IF EXISTS public.fact_sales
    ADD CONSTRAINT fk_sales_household FOREIGN KEY (household_id)
    REFERENCES public.dim_household (household_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;

ALTER TABLE IF EXISTS public.fact_sales
    ADD CONSTRAINT fk_sales_product FOREIGN KEY (product_id)
    REFERENCES public.dim_product (product_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;

ALTER TABLE IF EXISTS public.fact_sales
    ADD CONSTRAINT fk_sales_time FOREIGN KEY (time_id)
    REFERENCES public.dim_time (time_id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;

END;
