BEGIN; -- начало транзакции;

DROP DATABASE IF EXISTS pizzeria;
CREATE DATABASE IF NOT EXISTS pizzeria;  -- Удалить, если существует, создать и использовать БД pizzeria;
USE pizzeria; 

-- Удалить, если существуют, сущности;
DROP TABLE IF EXISTS compound,
					 pizzaTypes,
					 pizza,
			         customer,
                     order_info,
                     orders,
                     delivers
;

/* Информация о курьерах.
Столбцы: имя, фамилия, город, тип доставок. 
delivery.id - PK и FK для orders.*/

CREATE TABLE delivery (
     id              INT                                           NOT NULL AUTO_INCREMENT,
     first_name      VARCHAR(20)                                   NOT NULL,
     last_name       VARCHAR(20)                                   NOT NULL,
     city            VARCHAR(15)                                   NOT NULL,
     delivery_type   ENUM ('Велокурьер', 'Пеший', 'Автокурьер')    NOT NULL,
     CONSTRAINT      pk_deliver                                    PRIMARY KEY (id)
);

/* Отношение с информацией о товаре.
Столбцы: размер, диаметр, вес, калории и КБЖУ на 100 грамм.
Информация для клиентов сайта/ресторана при выборе блюд.*/

CREATE TABLE pizza_types (
     id              INT                                           NOT NULL AUTO_INCREMENT,
     size            ENUM ('Большая', 'Средняя', 'Маленькая')      NOT NULL,
     diameter        INT                                           NOT NULL,
     weight          FLOAT                                         NOT NULL,
     calories        DECIMAL(5,2)                                  NOT NULL,
     protein         DECIMAL(5,2)                                  NOT NULL,
     fat             DECIMAL(5,2)                                  NOT NULL,
     carbohydrates   DECIMAL(5,2)                                  NOT NULL,
     CONSTRAINT      pk_types                                      PRIMARY KEY (id),
     CONSTRAINT      ch_diameter                                   CHECK (diameter IN (23, 32, 41))
);

/* Основное отношение товара. 
Столбцы: идентификатор - PK, название товара, type_id - FK для pizza_types.*/

CREATE TABLE pizza (
     pizza_id        INT                                           NOT NULL AUTO_INCREMENT,
     name            VARCHAR(20)                                   NOT NULL,
     type_id         INT                                           NOT NULL,
     CONSTRAINT      pk_product                                    PRIMARY KEY (pizza_id),
     CONSTRAINT      fk_type                                       FOREIGN KEY (type_id) REFERENCES pizza_types (id) ON DELETE CASCADE
);

/* Инфо клиентов.
Столбцы: идентификатор, имя, дата регмстрации, адрес. 
customer.id - FK для orders.*/

CREATE TABLE customer (
	id              INT                                            NOT NULL AUTO_INCREMENT,
	first_name      VARCHAR(20)                                    NOT NULL,
	last_name       VARCHAR(20)                                    NOT NULL,
    gender          ENUM ('Male', 'Female')                        NOT NULL,
	birthday        DATE                                           NOT NULL,
    reg_date        DATETIME                                       NOT NULL DEFAULT CURRENT_TIMESTAMP,
	city            VARCHAR(15)                                    NOT NULL,
	district        VARCHAR(20)                                    DEFAULT NULL,
	street          VARCHAR(30)                                    NOT NULL,
	building        INT                                            NOT NULL,
	apartment       INT                                            DEFAULT NULL,
	CONSTRAINT      pk_customer                                    PRIMARY KEY (id)
); 

/* Инфо о заказах. Основное аналитическое отношение.
Храним номер, время и статус заказа, номер клиента и курьера.
order.id - FK для order_items.*/

CREATE TABLE orders ( 
	id              INT                                            NOT NULL AUTO_INCREMENT,
	customer_id     INT                                            NOT NULL,
	date_time       DATETIME                                       NOT NULL,
	deliver_id      INT                                            DEFAULT NULL,
	payment_method  ENUM ('Дебетовая карта', 'Наличные', 'СБП'),
    status          ENUM ('Обработка', 'Доставлен', 'Отменен')     NOT NULL DEFAULT ('Обработка'),
	CONSTRAINT      fk_customer                                    FOREIGN KEY (customer_id) REFERENCES customer (id),
	CONSTRAINT      fk_deliver                                     FOREIGN KEY (deliver_id) REFERENCES delivery (id),
	CONSTRAINT      pk_orders                                      PRIMARY KEY (id)
);

-- Связывающее отношение заказа и товара. Используется для сохранения  

CREATE TABLE order_items (
	order_id        INT                                            NOT NULL,
	pizza_id        INT                                            NOT NULL,
    price           DECIMAL(6,2)                                   NOT NULL,
	pizza_amount    INT                                            NOT NULL,
    CONSTRAINT      check_price                                    CHECK (price > 0),
	CONSTRAINT      fk_pizza                                       FOREIGN KEY (pizza_id) REFERENCES pizza (pizza_id),
	CONSTRAINT      fk_orders                                      FOREIGN KEY (order_id) REFERENCES orders (id),
	CONSTRAINT      pk_orders_items                                PRIMARY KEY (order_id, pizza_id),
	CONSTRAINT      ch_amount                                      CHECK (pizza_amount > 0)
);

SAVEPOINT sp1;

-- Оптимизация запросов. 

-- orders.
CREATE INDEX idx_orders_date_time ON orders (date_time);
CREATE INDEX idx_orders_customer_date ON orders (customer_id, date_time);

-- order_items.
CREATE INDEX idx_order_items_pizza ON order_items (pizza_id);

-- customer.
CREATE INDEX idx_customer_reg_date ON customer (reg_date);

/* 
Представления для аналитики. 
1 - продажи последнего дня;
2 - новые клиенты за последний месяц;
3 - суммарные продажи групп за весь период;
4 - оценка эффективности курьера на основе всех и завершенных заказов;
5 - клиенты без заказов более одного года.
*/

CREATE VIEW last_day_sales AS (
SELECT
	p.name,
    p.type_id,
    COUNT(DISTINCT(oi.order_id)) AS total_orders,
	SUM(oi.pizza_amount) AS count_sold,
    ROUND(SUM(oi.pizza_amount * oi.price), 2) AS total_sales_sum
FROM orders o
INNER JOIN order_items as oi
ON o.id = oi.order_id
INNER JOIN pizza AS p
ON oi.pizza_id = p.pizza_id
WHERE date_time >= CURRENT_DATE()
AND date_time < CURRENT_DATE + INTERVAL 1 DAY
GROUP BY p.name, p.type_id
);

CREATE VIEW new_customers_per_month AS (
SELECT 
	city, 
    COUNT(id) AS new_customers
FROM customer
WHERE reg_date >= CURRENT_DATE() - INTERVAL 30 DAY
GROUP BY city
);

CREATE VIEW total_orders AS (
SELECT 	
	oi.pizza_id,
	p.name, 
    COUNT(oi.order_id) AS total_saled, 
    SUM(oi.price) AS orders_sum
FROM pizza AS p
INNER JOIN order_items AS oi
ON p.pizza_id = oi.pizza_id
INNER JOIN orders AS o
ON oi.order_id = o.id
WHERE o.status = 'Доставлен'
GROUP BY p.pizza_id, p.name
);

CREATE VIEW delivery_efficiency AS (
SELECT 
	o.deliver_id,
    d.first_name,
    d.last_name,
    COUNT(o.id) AS total_orders,
    SUM(
		CASE 
			WHEN o.status = 'Доставлен' THEN 1 ELSE 0
		END
    ) AS delivered_orders,
    SUM(
		CASE 
			WHEN o.status = 'Отменен' THEN 1 ELSE 0
		END
	) AS cancelled_orders,
    ROUND(SUM(CASE WHEN o.status = 'Доставлен' THEN 1 ELSE 0 END) / COUNT(o.id), 2
    ) AS delivery_success_rate
FROM delivery AS d
LEFT JOIN orders AS o
ON d.id = o.deliver_id
GROUP BY 1, 2, 3
);

CREATE VIEW unactive_clients AS 
SELECT 
	c.id,
	c.first_name,
    c.last_name,
    c.reg_date,
    c.birthday,
    MAX(o.date_time) AS last_order
FROM customer AS c
LEFT JOIN orders AS o
ON c.id = o.customer_id
GROUP BY 1, 2, 3, 4
HAVING MAX(o.date_time) <= CURRENT_DATE - INTERVAL 1 YEAR
OR MAX(o.date_time) IS NULL
ORDER BY last_order;

COMMIT; -- конец транзакции.