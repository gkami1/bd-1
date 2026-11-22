/*
================================================================================
  Студент:  Габдулхаков Камиль Фанисович
  Вариант:  6

  Домашнее задание к первому модулю.

  Условие задания:
  Описание расписания пригородных электропоездов одного направления.
  Включает в себя: станции, график движения электропоездов, стоимости билетов.
  Станции описываются: названием, тарифной зоной, порядковым номером на
  направлении. График движения электропоездов описывается: указанием станции
  начала маршрута, указанием станции, завершающей маршрут, списком станций,
  на которых поезд не останавливается, временем прибытия на каждую станцию,
  на которой поезд останавливается, списком дней недели, по которым данный
  маршрут работает. Стоимости билетов описываются: количеством пересекаемых
  зон и, непосредственно, самой стоимостью.
  Поезда двигаются в одном направлении, но по мере удаления от начальной
  станции ветка может разделяться на несколько подветок.

  СУБД: PostgreSQL.

  Модели:
    branches        - ветки направления (основная ветка и подветки);
    tariff_zones    - тарифные зоны;
    stations        - станции;
    fares           - стоимость билета в зависимости от числа пересекаемых зон;
    days_of_week    - справочник дней недели;
    routes          - маршруты (нитки графика) электропоездов;
    route_days      - дни недели, по которым работает маршрут (M:N);
    route_stations  - станции маршрута: остановки со временем прибытия
                      и станции, которые поезд проезжает без остановки.
================================================================================
*/

DROP TABLE IF EXISTS route_stations CASCADE;
DROP TABLE IF EXISTS route_days     CASCADE;
DROP TABLE IF EXISTS routes         CASCADE;
DROP TABLE IF EXISTS days_of_week   CASCADE;
DROP TABLE IF EXISTS fares          CASCADE;
DROP TABLE IF EXISTS stations       CASCADE;
DROP TABLE IF EXISTS tariff_zones   CASCADE;
DROP TABLE IF EXISTS branches       CASCADE;


-- -----------------------------------------------------------------------------
-- Ветки направления. Основная ветка не имеет родителя; подветка отходит от
-- родительской ветки на станции разветвления (fork_station_id).
-- -----------------------------------------------------------------------------
CREATE TABLE branches (
    branch_id        SERIAL       PRIMARY KEY,
    name             VARCHAR(100) NOT NULL UNIQUE,
    parent_branch_id INTEGER      REFERENCES branches (branch_id)
                                  ON UPDATE CASCADE ON DELETE RESTRICT,
    fork_station_id  INTEGER,     -- FK добавляется после создания stations
    CONSTRAINT chk_branches_not_self_parent
        CHECK (parent_branch_id IS NULL OR parent_branch_id <> branch_id),
    -- у основной ветки нет точки разветвления, у подветки она обязательна
    CONSTRAINT chk_branches_fork
        CHECK ((parent_branch_id IS NULL AND fork_station_id IS NULL)
            OR (parent_branch_id IS NOT NULL AND fork_station_id IS NOT NULL))
);


-- -----------------------------------------------------------------------------
-- Тарифные зоны.
-- -----------------------------------------------------------------------------
CREATE TABLE tariff_zones (
    zone_number SMALLINT     PRIMARY KEY CHECK (zone_number > 0),
    name        VARCHAR(50)
);


-- -----------------------------------------------------------------------------
-- Станции. Порядковый номер на направлении считается от начальной станции
-- направления и уникален в пределах ветки.
-- -----------------------------------------------------------------------------
CREATE TABLE stations (
    station_id   SERIAL       PRIMARY KEY,
    name         VARCHAR(100) NOT NULL UNIQUE,
    zone_number  SMALLINT     NOT NULL REFERENCES tariff_zones (zone_number)
                              ON UPDATE CASCADE ON DELETE RESTRICT,
    order_number SMALLINT     NOT NULL CHECK (order_number > 0),
    branch_id    INTEGER      NOT NULL REFERENCES branches (branch_id)
                              ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT uq_stations_branch_order UNIQUE (branch_id, order_number)
);

ALTER TABLE branches
    ADD CONSTRAINT fk_branches_fork_station
    FOREIGN KEY (fork_station_id) REFERENCES stations (station_id)
    ON UPDATE CASCADE ON DELETE RESTRICT;


-- -----------------------------------------------------------------------------
-- Стоимость билета: количество пересекаемых зон -> стоимость.
-- -----------------------------------------------------------------------------
CREATE TABLE fares (
    zones_count SMALLINT      PRIMARY KEY CHECK (zones_count > 0),
    price       NUMERIC(10,2) NOT NULL CHECK (price >= 0)
);


-- -----------------------------------------------------------------------------
-- Справочник дней недели (1 - понедельник ... 7 - воскресенье, ISO 8601).
-- -----------------------------------------------------------------------------
CREATE TABLE days_of_week (
    day_id     SMALLINT    PRIMARY KEY CHECK (day_id BETWEEN 1 AND 7),
    name       VARCHAR(15) NOT NULL UNIQUE,
    short_name CHAR(2)     NOT NULL UNIQUE
);

INSERT INTO days_of_week (day_id, name, short_name) VALUES
    (1, 'Понедельник', 'Пн'),
    (2, 'Вторник',     'Вт'),
    (3, 'Среда',       'Ср'),
    (4, 'Четверг',     'Чт'),
    (5, 'Пятница',     'Пт'),
    (6, 'Суббота',     'Сб'),
    (7, 'Воскресенье', 'Вс');


-- -----------------------------------------------------------------------------
-- Маршруты электропоездов (нитки графика движения).
-- -----------------------------------------------------------------------------
CREATE TABLE routes (
    route_id         SERIAL      PRIMARY KEY,
    train_number     VARCHAR(10) NOT NULL UNIQUE,
    start_station_id INTEGER     NOT NULL REFERENCES stations (station_id)
                                 ON UPDATE CASCADE ON DELETE RESTRICT,
    end_station_id   INTEGER     NOT NULL REFERENCES stations (station_id)
                                 ON UPDATE CASCADE ON DELETE RESTRICT,
    is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_routes_different_stations
        CHECK (start_station_id <> end_station_id)
);


-- -----------------------------------------------------------------------------
-- Дни недели, по которым работает маршрут (связь M:N routes <-> days_of_week).
-- -----------------------------------------------------------------------------
CREATE TABLE route_days (
    route_id INTEGER  NOT NULL REFERENCES routes (route_id)
                      ON UPDATE CASCADE ON DELETE CASCADE,
    day_id   SMALLINT NOT NULL REFERENCES days_of_week (day_id)
                      ON UPDATE CASCADE ON DELETE RESTRICT,
    PRIMARY KEY (route_id, day_id)
);


-- -----------------------------------------------------------------------------
-- Станции маршрута. Одна таблица хранит оба списка из условия:
--   is_stop = TRUE  -> поезд останавливается, время прибытия обязательно;
--   is_stop = FALSE -> станция в списке проезжаемых без остановки,
--                      время прибытия не указывается.
-- Так станция маршрута не может одновременно оказаться в обоих списках.
-- -----------------------------------------------------------------------------
CREATE TABLE route_stations (
    route_id     INTEGER NOT NULL REFERENCES routes (route_id)
                         ON UPDATE CASCADE ON DELETE CASCADE,
    station_id   INTEGER NOT NULL REFERENCES stations (station_id)
                         ON UPDATE CASCADE ON DELETE RESTRICT,
    is_stop      BOOLEAN NOT NULL DEFAULT TRUE,
    arrival_time TIME,
    PRIMARY KEY (route_id, station_id),
    CONSTRAINT chk_route_stations_arrival
        CHECK ((is_stop AND arrival_time IS NOT NULL)
            OR (NOT is_stop AND arrival_time IS NULL))
);
