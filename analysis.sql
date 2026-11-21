-- analysis.sql
-- Анализ выручки и RFM-сегментации (Online Retail II, 2009-2011)
-- СУБД: PostgreSQL. Выполнять запросы сверху вниз.
-- =====================================================
-- retail_raw  -- таблица, в которую импортирован исходный CSV (Online Retail II).
-- Ожидаемые колонки: invoice_no, invoice_date, quantity, unit_price, customer_id.
-- Если названия отличаются — поправьте их в представлении retail_new ниже.

-- -----------------------------------------------------
-- Шаг 0. Рабочее представление с чистыми данными
-- Правила очистки (как в основном анализе):
--   1) убираем возвраты (quantity <= 0 и счета, начинающиеся с 'C');
--   2) убираем строки с нулевой/отрицательной ценой;
--   3) убираем заказы без customer_id (нет смысла включать их в RFM).
-- -----------------------------------------------------

CREATE OR REPLACE VIEW retail_new AS
SELECT
    invoice_no,
    invoice_date,
    EXTRACT(ISODOW FROM invoice_date)::int  AS invoice_weekday,  -- 1=Пн ... 7=Вс
    date_trunc('month', invoice_date)::date AS invoice_month,
    customer_id,
    quantity,
    unit_price,
    quantity * unit_price                   AS invoice_revenue
FROM retail_raw
WHERE quantity > 0
  AND unit_price > 0
  AND invoice_no NOT LIKE 'C%'
  AND customer_id IS NOT NULL;


-- -----------------------------------------------------
-- Запрос 1. Выручка по месяцам (линейный график)
-- Результат: колонки month, revenue
-- -----------------------------------------------------
SELECT
    to_char(invoice_month, 'YYYY-MM') AS month,
    ROUND(SUM(invoice_revenue)::numeric, 0) AS revenue
FROM retail_new
GROUP BY invoice_month
ORDER BY invoice_month;


-- -----------------------------------------------------
-- Запрос 2. YoY-сравнение 2010 vs 2011 (столбчатая диаграмма)
-- Внимание: декабрь 2011 — неполный месяц (данные до 09.12.2011),
-- на графике его столбик выделяется серым с пометкой "Неполный месяц".
-- Результат: колонки month_num, revenue_2010, revenue_2011
-- -----------------------------------------------------
SELECT
    EXTRACT(MONTH FROM invoice_month)::int AS month_num,
    ROUND(SUM(invoice_revenue) FILTER (WHERE EXTRACT(YEAR FROM invoice_month) = 2010)::numeric, 0) AS revenue_2010,
    ROUND(SUM(invoice_revenue) FILTER (WHERE EXTRACT(YEAR FROM invoice_month) = 2011)::numeric, 0) AS revenue_2011
FROM retail_new
GROUP BY 1
ORDER BY 1;


-- -----------------------------------------------------
-- Запрос 3. Выручка по дням недели, суммарно за 2009-2011 (горизонтальная гистограмма)
-- Результат: колонки weekday_name, total_revenue
-- -----------------------------------------------------
SELECT
    invoice_weekday,
    CASE invoice_weekday
        WHEN 1 THEN 'Понедельник'
        WHEN 2 THEN 'Вторник'
        WHEN 3 THEN 'Среда'
        WHEN 4 THEN 'Четверг'
        WHEN 5 THEN 'Пятница'
        WHEN 6 THEN 'Суббота'
        WHEN 7 THEN 'Воскресенье'
    END AS weekday_name,
    ROUND(SUM(invoice_revenue)::numeric, 0) AS total_revenue
FROM retail_new
GROUP BY invoice_weekday
ORDER BY invoice_weekday;


-- -----------------------------------------------------
-- Запрос 4. RFM-сегментация по давности покупок (круговая диаграмма)
-- Опорная дата — последняя дата в данных (2011-12-09), а не текущая дата:
-- датасет исторический, иначе все клиенты были бы "ушедшими".
-- Результат: колонки segment, segment_revenue, share_pct
-- -----------------------------------------------------
WITH last_purchase AS (
    SELECT
        customer_id,
        MAX(invoice_date)   AS last_order_date,
        SUM(invoice_revenue) AS client_revenue
    FROM retail_new
    GROUP BY customer_id
),
rfm AS (
    SELECT
        lp.customer_id,
        lp.client_revenue,
        CASE
            WHEN lp.last_order_date >= ref.reference_date - INTERVAL '90 days'
                THEN 'активные (0-90 дн)'
            WHEN lp.last_order_date >= ref.reference_date - INTERVAL '365 days'
                THEN 'в зоне риска (90-365 дн)'
            ELSE 'ушедшие (>365 дн)'
        END AS segment
    FROM last_purchase lp
    CROSS JOIN (SELECT MAX(invoice_date) AS reference_date FROM retail_new) ref
)
SELECT
    segment,
    ROUND(SUM(client_revenue)::numeric, 0) AS segment_revenue,
    ROUND(SUM(client_revenue) * 100.0 / SUM(SUM(client_revenue)) OVER (), 1) AS share_pct
FROM rfm
GROUP BY segment
ORDER BY segment_revenue DESC;
