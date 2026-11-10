import GRDB

/// Миграции схемы. Старые миграции не меняются — только новые сверху вниз.
enum Migrations {
    static let initial = "v1_initial"
    static let habitsAndEpics = "v2_habitsAndEpics"

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

        return migrator
    }
}
