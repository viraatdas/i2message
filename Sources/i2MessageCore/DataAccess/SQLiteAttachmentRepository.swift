import Foundation

public actor SQLiteAttachmentRepository: AttachmentRepository {
    private let store: ReadOnlyMessagesStore

    public init(store: ReadOnlyMessagesStore) {
        self.store = store
    }

    public func attachment(id: AttachmentID) async throws -> MessageAttachment {
        guard let attachmentRowID = MessagesIdentifier.rowID(from: id) else {
            throw I2MessageError.notFound(resource: "Attachment", id: id.rawValue)
        }

        let attachmentsDirectoryURL = store.configuration.attachmentsDirectoryURL
        let attachment = try await store.read { connection, schema in
            guard schema.hasTable("attachment") else {
                throw I2MessageError.notFound(resource: "Attachment", id: id.rawValue)
            }

            let sql = Self.attachmentSelectSQL(schema: schema, whereClause: "a.ROWID = ?")
            return try connection.query(sql, [.int64(attachmentRowID)]).first.map {
                Self.mapAttachment($0, attachmentsDirectoryURL: attachmentsDirectoryURL)
            }
        }

        guard let attachment else {
            throw I2MessageError.notFound(resource: "Attachment", id: id.rawValue)
        }

        return attachment
    }

    public func attachments(for messageID: MessageID) async throws -> [MessageAttachment] {
        guard let messageRowID = MessagesIdentifier.rowID(from: messageID) else {
            return []
        }

        let grouped = try await attachments(forMessageRowIDs: [messageRowID])
        return grouped[messageRowID] ?? []
    }

    func attachments(forMessageRowIDs messageRowIDs: [Int64]) async throws -> [Int64: [MessageAttachment]] {
        guard !messageRowIDs.isEmpty else {
            return [:]
        }

        let attachmentsDirectoryURL = store.configuration.attachmentsDirectoryURL
        return try await store.read { connection, schema in
            guard schema.hasTable("attachment"), schema.hasTable("message_attachment_join") else {
                return [:]
            }

            let placeholders = Array(repeating: "?", count: messageRowIDs.count).joined(separator: ", ")
            let sql = Self.attachmentSelectSQL(schema: schema, whereClause: "maj.message_id IN (\(placeholders))")
            let rows = try connection.query(sql, messageRowIDs.map(SQLiteBindValue.int64))
            var grouped: [Int64: [MessageAttachment]] = [:]

            for row in rows {
                guard let messageRowID = row["message_rowid"].int64 else {
                    continue
                }

                grouped[messageRowID, default: []].append(
                    Self.mapAttachment(row, attachmentsDirectoryURL: attachmentsDirectoryURL)
                )
            }

            return grouped
        }
    }

    private static func attachmentSelectSQL(schema: MessagesDatabaseSchema, whereClause: String) -> String {
        let filename = schema.column("filename", in: "attachment", qualifiedBy: "a")
        let uti = schema.coalescedColumns(["uti", "mime_type"], in: "attachment", qualifiedBy: "a")
        let mimeType = schema.column("mime_type", in: "attachment", qualifiedBy: "a")
        let transferName = schema.coalescedColumns(["transfer_name", "name"], in: "attachment", qualifiedBy: "a")
        let totalBytes = schema.coalescedColumns(["total_bytes", "byte_count"], in: "attachment", qualifiedBy: "a")
        let width = schema.column("width", in: "attachment", qualifiedBy: "a")
        let height = schema.column("height", in: "attachment", qualifiedBy: "a")
        let duration = schema.column("duration", in: "attachment", qualifiedBy: "a")

        let joinClause = schema.hasTable("message_attachment_join")
            ? "LEFT JOIN message_attachment_join maj ON maj.attachment_id = a.ROWID"
            : "LEFT JOIN (SELECT NULL AS message_id, NULL AS attachment_id) maj ON 0"

        return """
        SELECT
            a.ROWID AS attachment_rowid,
            maj.message_id AS message_rowid,
            \(filename.sql) AS filename,
            \(uti.sql) AS uti,
            \(mimeType.sql) AS mime_type,
            \(transferName.sql) AS transfer_name,
            \(totalBytes.sql) AS total_bytes,
            \(width.sql) AS width,
            \(height.sql) AS height,
            \(duration.sql) AS duration
        FROM attachment a
        \(joinClause)
        WHERE \(whereClause)
        ORDER BY maj.message_id DESC, a.ROWID ASC
        """
    }

    private static func mapAttachment(_ row: SQLiteRow, attachmentsDirectoryURL: URL?) -> MessageAttachment {
        let attachmentRowID = row["attachment_rowid"].int64 ?? 0
        let messageRowID = row["message_rowid"].int64
        let rawFilename = row["filename"].string
        let transferName = row["transfer_name"].string
        let filename = MessagesMapping.attachmentFilename(
            rawFilename: rawFilename,
            transferName: transferName,
            attachmentsDirectoryURL: attachmentsDirectoryURL
        )
        let uti = row["uti"].string
        let mimeType = row["mime_type"].string
        let width = row["width"].int
        let height = row["height"].int
        let dimensions: AttachmentDimensions?

        if let width, let height, width > 0, height > 0 {
            dimensions = AttachmentDimensions(width: width, height: height)
        } else {
            dimensions = nil
        }

        return MessageAttachment(
            id: MessagesIdentifier.attachmentID(rowID: attachmentRowID),
            messageID: messageRowID.map(MessagesIdentifier.messageID(rowID:)),
            kind: MessagesMapping.attachmentKind(
                filename: filename.displayName,
                uti: uti,
                mimeType: mimeType,
                transferName: transferName
            ),
            filename: filename.displayName,
            uniformTypeIdentifier: uti ?? mimeType,
            byteCount: row["total_bytes"].int64,
            fileURL: filename.fileURL,
            thumbnailURL: nil,
            dimensions: dimensions,
            duration: row["duration"].double,
            transferState: filename.transferState
        )
    }
}
