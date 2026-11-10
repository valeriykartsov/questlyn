import GRDB

/// Миграции схемы. Старые миграции не меняются — только новые сверху вниз.
enum Migrations {
    static let initial = "v1_initial"
    static let habitsAndEpics = "v2_habitsAndEpics"
    static let honestProgress = "v3_honestProgress"
    static let activities = "v4_activities"
    static let heroOutfit = "v5_heroOutfit"
    static let vitals = "v6_vitals"
    static let chronicle = "v7_chronicle"

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration(initial) { db in
            try db.create(table: "hero") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().check { length($0) > 0 }
                t.column("classTitle", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "profession") { t in
                t.primaryKey("id", .text)
                t.belongsTo("hero", onDelete: .cascade).notNull()
                t.column("title", .text).notNull()
                t.column("slot", .integer).notNull().check { (1...3).contains($0) }
                t.column("catalogItemId", .text)
                t.column("catalogVersion", .text)
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
            }
            // Слоты активных профессий героя уникальны.
            try db.execute(sql: """
                CREATE UNIQUE INDEX profession_activeSlot ON profession(heroId, slot) WHERE isActive = 1
                """)

            try db.create(table: "professionAttribute") { t in
                t.belongsTo("profession", onDelete: .cascade).notNull()
                t.column("position", .integer).notNull().check { (1...3).contains($0) }
                t.column("attribute", .text).notNull()
                    .check(sql: "attribute IN ('STR', 'END', 'INT', 'MNT', 'CHR')")
                t.primaryKey(["professionId", "position"])
                t.uniqueKey(["professionId", "attribute"])
            }

            try db.create(table: "skill") { t in
                t.primaryKey("id", .text)
                t.belongsTo("profession", onDelete: .restrict).notNull()
                t.column("title", .text).notNull().check { length($0) > 0 }
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "quest") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull().check { length($0) > 0 }
                t.column("details", .text)
                t.column("priority", .text).notNull().defaults(to: "medium")
                    .check(sql: "priority IN ('low', 'medium', 'high')")
                t.belongsTo("skill", onDelete: .setNull)
                t.column("dueDate", .text).indexed()
                t.column("dueTime", .text)
                t.column("timezoneId", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.check(sql: "dueTime IS NULL OR dueDate IS NOT NULL")
            }

            // Факт: выполнение квеста. Отмена ставит undoneAt, строка остаётся (Летопись).
            try db.create(table: "questCompletion") { t in
                t.primaryKey("id", .text)
                t.belongsTo("quest", onDelete: .cascade).notNull()
                t.column("completedAt", .datetime).notNull()
                t.column("localDate", .text).notNull().indexed()
                t.column("timezoneId", .text).notNull()
                t.column("undoneAt", .datetime)
                t.column("classSnapshot", .jsonText).notNull()
            }
            // Не больше одного активного выполнения на квест.
            try db.execute(sql: """
                CREATE UNIQUE INDEX questCompletion_active ON questCompletion(questId) WHERE undoneAt IS NULL
                """)

            // Производное: начисления прогресса. Идемпотентность — уникальный ключ.
            try db.create(table: "progressGrant") { t in
                t.primaryKey("id", .text)
                t.column("sourceType", .text).notNull()
                t.column("sourceId", .text).notNull()
                t.column("ruleVersion", .text).notNull()
                t.column("targetKind", .text).notNull().check(sql: "targetKind IN ('attribute', 'skill')")
                t.column("attribute", .text)
                t.column("skillId", .text)
                // Ключ цели без NULL, чтобы уникальность работала и для навыков, и для атрибутов.
                t.column("targetKey", .text).notNull()
                t.column("amountCenti", .integer).notNull()
                t.column("reason", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["sourceType", "sourceId", "ruleVersion", "targetKey"])
                t.check(sql: """
                    (targetKind = 'attribute' AND attribute IS NOT NULL AND skillId IS NULL)
                    OR (targetKind = 'skill' AND skillId IS NOT NULL AND attribute IS NULL)
                    """)
            }
            try db.create(index: "progressGrant_source", on: "progressGrant", columns: ["sourceType", "sourceId"])
        }

        // Этап 2: Epic, Daily и Weekly Quest, отметки привычек.
        migrator.registerMigration(habitsAndEpics) { db in
            try db.create(table: "epic") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull().check { length($0) > 0 }
                t.column("details", .text)
                t.column("deadline", .text)
                t.column("completedAt", .datetime)
                t.column("createdAt", .datetime).notNull()
            }
            try db.alter(table: "quest") { t in
                t.add(column: "epicId", .text).references("epic", onDelete: .setNull)
            }
            try db.create(index: "quest_epicId", on: "quest", columns: ["epicId"])

            try db.create(table: "habit") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull().check(sql: "kind IN ('daily', 'weekly')")
                t.column("title", .text).notNull().check { length($0) > 0 }
                t.column("details", .text)
                t.belongsTo("skill", onDelete: .setNull)
                // Дни недели через запятую, 1 — понедельник.
                t.column("weekdays", .text).notNull()
                t.column("targetPerWeek", .integer).notNull().check { $0 >= 1 }
                t.column("time", .text)
                t.column("timezoneId", .text).notNull()
                t.column("startDate", .text).notNull()
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
            }

            // Факт: отметка привычки. Отмена ставит undoneAt (Летопись).
            try db.create(table: "habitOccurrence") { t in
                t.primaryKey("id", .text)
                t.belongsTo("habit", onDelete: .cascade).notNull()
                t.column("localDate", .text).notNull()
                t.column("completedAt", .datetime).notNull()
                t.column("timezoneId", .text).notNull()
                t.column("undoneAt", .datetime)
                t.column("classSnapshot", .jsonText).notNull()
            }
            try db.create(index: "habitOccurrence_habitDate", on: "habitOccurrence", columns: ["habitId", "localDate"])
        }

        // Этап 3: дата начисления для спада, внешность героя, мастерство навыка.
        migrator.registerMigration(honestProgress) { db in
            try db.alter(table: "hero") { t in
                t.add(column: "hair", .text).notNull().defaults(to: "dark")
                t.add(column: "skin", .text).notNull().defaults(to: "medium")
            }
            try db.alter(table: "progressGrant") { t in
                t.add(column: "localDate", .text)
            }
            // Дата факта для уже записанных начислений.
            try db.execute(sql: """
                UPDATE progressGrant SET localDate = (SELECT localDate FROM questCompletion WHERE questCompletion.id = progressGrant.sourceId)
                WHERE sourceType = 'questCompletion';
                UPDATE progressGrant SET localDate = (SELECT localDate FROM habitOccurrence WHERE habitOccurrence.id = progressGrant.sourceId)
                WHERE sourceType = 'habitOccurrence';
                UPDATE progressGrant SET localDate = date(substr(sourceId, 29, 4) || '-' || substr(sourceId, 33, 2) || '-' || substr(sourceId, 35, 2), '+7 days')
                WHERE sourceType = 'weeklyDiscipline';
                UPDATE progressGrant SET localDate = substr(createdAt, 1, 10) WHERE localDate IS NULL;
                """)
            try db.create(index: "progressGrant_localDate", on: "progressGrant", columns: ["localDate"])

            try db.create(table: "skillMastery") { t in
                t.primaryKey("id", .text)
                t.belongsTo("skill", onDelete: .cascade).notNull()
                t.column("value", .integer).notNull().check { $0 >= 1 && $0 <= 5 }
                t.column("assessedAt", .datetime).notNull()
            }
        }

        // Этап 3.3: Activity — факт практики по шаблону.
        migrator.registerMigration(activities) { db in
            try db.create(table: "activity") { t in
                t.primaryKey("id", .text)
                t.column("templateId", .text).notNull()
                t.belongsTo("skill", onDelete: .setNull)
                t.column("durationMinutes", .integer).notNull().check { $0 > 0 && $0 <= 1440 }
                t.column("creditedMinutes", .integer).notNull().check { $0 >= 0 && $0 <= 180 }
                t.column("localDate", .text).notNull().indexed()
                t.column("startedAt", .datetime).notNull()
                t.column("timezoneId", .text).notNull()
                t.column("questCompletionId", .text).references("questCompletion", onDelete: .setNull)
                t.column("classSnapshot", .jsonText).notNull()
                t.column("deletedAt", .datetime)
            }
        }

        // Этап 3.6: образ героя. Уже созданным героям — «Программист», как в макете выбора.
        migrator.registerMigration(heroOutfit) { db in
            try db.alter(table: "hero") { t in
                t.add(column: "outfit", .text).notNull().defaults(to: "coder")
            }
        }

        // Этап 4: сон, шаги и настройки «Здоровья героя» — факты для HP и MP.
        migrator.registerMigration(vitals) { db in
            try db.create(table: "sleepSession") { t in
                t.primaryKey("id", .text)
                t.column("wakeDate", .text).notNull().indexed()
                t.column("durationMinutes", .integer).notNull().check { $0 > 0 && $0 <= 1440 }
                t.column("bedtimeDeviationMinutes", .integer)
                t.column("startedAt", .datetime)
                t.column("endedAt", .datetime)
                t.column("source", .text).notNull().check { [SleepSourceValue.manual, SleepSourceValue.health].contains($0) }
                t.column("timezoneId", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "stepDay") { t in
                t.primaryKey("date", .text)
                t.column("steps", .integer).notNull().check { $0 >= 0 }
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }

        // Этап 5: вехи Летописи — единственное, что Летопись хранит сама.
        migrator.registerMigration(chronicle) { db in
            try db.create(table: "chronicleEntry") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("key", .text).notNull().indexed()
                t.column("title", .text).notNull()
                t.column("occurredAt", .datetime).notNull()
                t.column("localDate", .text).notNull().indexed()
                t.column("ruleVersion", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("cancelledAt", .datetime)
                t.column("recalculatedBy", .text)
            }
        }

        return migrator
    }
}

private enum SleepSourceValue {
    static let manual = "manual"
    static let health = "health"
}
