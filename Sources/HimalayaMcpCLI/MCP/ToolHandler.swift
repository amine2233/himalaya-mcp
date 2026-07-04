import App
import AppConfiguration
import CascadeKit
import Foundation
import MCP

/// Bridges a strongly-typed `Request` to the string-keyed, text-returning world
/// of MCP `tools/call`.
///
/// A `Request` has an `associatedtype`, so a heterogeneous list of them can't be
/// dispatched uniformly. Each `ToolHandler` erases one command into a closure
/// that decodes its typed `Input` from the call arguments, runs it, and returns
/// text — the small, explicit cost of the protocol approach.
struct ToolHandler: Sendable {
    let tool: Tool
    /// Whether this tool is gated behind the experimental feature flag.
    let isExperimental: Bool
    let call: @Sendable (CallTool.Parameters, Application) async throws -> String

    init(
        tool: Tool,
        isExperimental: Bool = false,
        call: @escaping @Sendable (CallTool.Parameters, Application) async throws -> String
    ) {
        self.tool = tool
        self.isExperimental = isExperimental
        self.call = call
    }
}

extension ToolHandler {
    /// Every tool the server knows about, before experimental gating.
    static let all: [ToolHandler] = [
        .listEmails, .searchEmails, .readEmail, .readEmailHtml,
        .listFolders, .createFolder, .deleteFolder,
        .flagEmail, .moveEmail,
        .composeEmail, .draftReply, .sendEmail, .sendTemplate,
        .listAttachments, .downloadAttachment,
        .deleteEmail
    ]

    /// The tools visible for the given flags: experimental tools are hidden
    /// unless the experimental feature flag is enabled.
    static func visible(featureFlags: FeatureFlags) -> [ToolHandler] {
        all.filter { !$0.isExperimental || featureFlags.experimentalEnabled }
    }
}

extension ToolHandler {
    /// Shared schema for a `folder` argument.
    private static let folderProperty: Value = .object([
        "type": .string("string"),
        "description": .string("Folder name. Defaults to INBOX.")
    ])

    /// Shared schema for an `account` argument.
    private static let accountProperty: Value = .object([
        "type": .string("string"),
        "description": .string("Account name. Defaults to the configured default account.")
    ])

    static let listEmails = ToolHandler(
        tool: Tool(
            name: "list_emails",
            description: "List envelopes in a folder via himalaya.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "folder": folderProperty,
                    "page_size": .object([
                        "type": .string("integer"),
                        "description": .string("Number of envelopes per page.")
                    ]),
                    "page": .object([
                        "type": .string("integer"),
                        "description": .string("1-based page number.")
                    ]),
                    "account": accountProperty
                ])
            ])
        ),
        call: { params, application in
            let input = try decodeArguments(ListEmailsRequest.Input.self, from: params.arguments)
            return try await ListEmailsRequest().execute(input, in: application)
        }
    )

    static let searchEmails = ToolHandler(
        tool: Tool(
            name: "search_emails",
            description: "Search envelopes with a himalaya filter/sort query (e.g. \"from alice and subject invoice\").",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string(
                            "himalaya filter/sort query, e.g. `subject invoice order by date desc`."
                        )
                    ]),
                    "folder": folderProperty,
                    "account": accountProperty
                ]),
                "required": .array([.string("query")])
            ])
        ),
        call: { params, application in
            let input = try decodeArguments(SearchEmailsRequest.Input.self, from: params.arguments)
            return try await SearchEmailsRequest().execute(input, in: application)
        }
    )

    static let readEmail = ToolHandler(
        tool: Tool(
            name: "read_email",
            description: "Read the plain-text body of a message by id.",
            inputSchema: readSchema
        ),
        call: { params, application in
            let input = try decodeArguments(ReadEmailRequest.Input.self, from: params.arguments)
            return try await ReadEmailRequest().execute(input, in: application)
        }
    )

    static let readEmailHtml = ToolHandler(
        tool: Tool(
            name: "read_email_html",
            description: "Read the HTML body of a message by id.",
            inputSchema: readSchema
        ),
        call: { params, application in
            let input = try decodeArguments(ReadEmailHtmlRequest.Input.self, from: params.arguments)
            return try await ReadEmailHtmlRequest().execute(input, in: application)
        }
    )

    /// Shared input schema for the read tools: a required `id` plus optional
    /// `folder` and `account`.
    private static let readSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "id": .object([
                "type": .string("string"),
                "description": .string("Envelope id of the message to read.")
            ]),
            "folder": folderProperty,
            "account": accountProperty
        ]),
        "required": .array([.string("id")])
    ])

    // MARK: Folders

    static let listFolders = ToolHandler(
        tool: Tool(
            name: "list_folders",
            description: "List all folders.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["account": accountProperty])
            ])
        ),
        call: { params, application in
            let input = try decodeArguments(ListFoldersRequest.Input.self, from: params.arguments)
            return try await ListFoldersRequest().execute(input, in: application)
        }
    )

    static let createFolder = ToolHandler(
        tool: Tool(
            name: "create_folder",
            description: "Create a new folder.",
            inputSchema: Self.folderNameSchema(description: "Name of the folder to create.")
        ),
        call: { params, application in
            let input = try decodeArguments(CreateFolderRequest.Input.self, from: params.arguments)
            return try await CreateFolderRequest().execute(input, in: application)
        }
    )

    static let deleteFolder = ToolHandler(
        tool: Tool(
            name: "delete_folder",
            description: "Delete a folder.",
            inputSchema: Self.folderNameSchema(description: "Name of the folder to delete.")
        ),
        call: { params, application in
            let input = try decodeArguments(DeleteFolderRequest.Input.self, from: params.arguments)
            return try await DeleteFolderRequest().execute(input, in: application)
        }
    )

    // MARK: Flags & moving

    static let flagEmail = ToolHandler(
        tool: Tool(
            name: "flag_email",
            description: "Add or remove flags (e.g. Seen, Flagged, Answered) on a message.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "id": .object([
                        "type": .string("string"),
                        "description": .string("Envelope id to flag.")
                    ]),
                    "flags": .object([
                        "type": .string("string"),
                        "description": .string("Space-separated flag names, e.g. `Seen Flagged`.")
                    ]),
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([.string("add"), .string("remove")]),
                        "description": .string("Whether to add or remove the flags.")
                    ]),
                    "folder": folderProperty
                ]),
                "required": .array([.string("id"), .string("flags"), .string("action")])
            ])
        ),
        call: { params, application in
            let input = try decodeArguments(FlagEmailRequest.Input.self, from: params.arguments)
            return try await FlagEmailRequest().execute(input, in: application)
        }
    )

    static let moveEmail = ToolHandler(
        tool: Tool(
            name: "move_email",
            description: "Move a message to another folder.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "id": .object([
                        "type": .string("string"),
                        "description": .string("Envelope id to move.")
                    ]),
                    "target_folder": .object([
                        "type": .string("string"),
                        "description": .string("Destination folder.")
                    ]),
                    "folder": folderProperty,
                    "account": accountProperty
                ]),
                "required": .array([.string("id"), .string("target_folder")])
            ])
        ),
        call: { params, application in
            let input = try decodeArguments(MoveEmailRequest.Input.self, from: params.arguments)
            return try await MoveEmailRequest().execute(input, in: application)
        }
    )

    // MARK: Composing & sending

    static let composeEmail = ToolHandler(
        tool: Tool(
            name: "compose_email",
            description: "Compose a new email template (does not send). Returns a template for send_email.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "to": .object([
                        "type": .string("string"),
                        "description": .string("Recipient address.")
                    ]),
                    "subject": .object([
                        "type": .string("string"),
                        "description": .string("Subject line.")
                    ]),
                    "body": .object([
                        "type": .string("string"),
                        "description": .string("Plain-text body.")
                    ]),
                    "attachments": attachmentsProperty,
                    "account": accountProperty
                ]),
                "required": .array([.string("to"), .string("subject"), .string("body")])
            ])
        ),
        call: { params, application in
            let input = try decodeArguments(ComposeEmailRequest.Input.self, from: params.arguments)
            return try await ComposeEmailRequest().execute(input, in: application)
        }
    )

    static let draftReply = ToolHandler(
        tool: Tool(
            name: "draft_reply",
            description: "Generate a reply template for a message (does not send). Returns a template for send_email.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "id": .object([
                        "type": .string("string"),
                        "description": .string("Envelope id being replied to.")
                    ]),
                    "body": .object([
                        "type": .string("string"),
                        "description": .string("Optional body to prefill above the quoted original.")
                    ]),
                    "reply_all": .object([
                        "type": .string("boolean"),
                        "description": .string("Reply to all recipients rather than just the sender.")
                    ]),
                    "folder": folderProperty,
                    "account": accountProperty
                ]),
                "required": .array([.string("id")])
            ])
        ),
        call: { params, application in
            let input = try decodeArguments(DraftReplyRequest.Input.self, from: params.arguments)
            return try await DraftReplyRequest().execute(input, in: application)
        }
    )

    static let sendEmail = ToolHandler(
        tool: Tool(
            name: "send_email",
            description: "Send a message template. Requires confirm=true; irreversible.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "template": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Raw message/template to send (from compose_email or draft_reply)."
                        )
                    ]),
                    "attachments": attachmentsProperty,
                    "confirm": .object([
                        "type": .string("boolean"),
                        "description": .string("Must be true to actually send.")
                    ]),
                    "account": accountProperty
                ]),
                "required": .array([.string("template")])
            ])
        ),
        call: { params, application in
            let input = try decodeArguments(SendEmailRequest.Input.self, from: params.arguments)
            return try await SendEmailRequest().execute(input, in: application)
        }
    )

    static let sendTemplate = ToolHandler(
        tool: Tool(
            name: "send_template",
            description: "Send a himalaya template (headers + MML body) you author, inline or from a file. Requires confirm=true; irreversible.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "template": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The template text (headers + MML body). Use this or template_file."
                        )
                    ]),
                    "template_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to a file containing the template. Use this or template."
                        )
                    ]),
                    "attachments": attachmentsProperty,
                    "confirm": .object([
                        "type": .string("boolean"),
                        "description": .string("Must be true to actually send.")
                    ]),
                    "account": accountProperty
                ])
            ])
        ),
        call: { params, application in
            let input = try decodeArguments(SendTemplateRequest.Input.self, from: params.arguments)
            return try await SendTemplateRequest().execute(input, in: application)
        }
    )

    // MARK: Attachments

    static let listAttachments = ToolHandler(
        tool: Tool(
            name: "list_attachments",
            description: "List a message's attachments (names and sizes).",
            inputSchema: readSchema
        ),
        call: { params, application in
            let input = try decodeArguments(ListAttachmentsRequest.Input.self, from: params.arguments)
            return try await ListAttachmentsRequest().execute(input, in: application)
        }
    )

    static let downloadAttachment = ToolHandler(
        tool: Tool(
            name: "download_attachment",
            description: "Download a named attachment from a message and return its contents.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "id": .object([
                        "type": .string("string"),
                        "description": .string("Envelope id whose attachment to download.")
                    ]),
                    "filename": .object([
                        "type": .string("string"),
                        "description": .string("Name of the attachment to return.")
                    ]),
                    "folder": folderProperty,
                    "account": accountProperty
                ]),
                "required": .array([.string("id"), .string("filename")])
            ])
        ),
        call: { params, application in
            let input = try decodeArguments(DownloadAttachmentRequest.Input.self, from: params.arguments)
            return try await DownloadAttachmentRequest().execute(input, in: application)
        }
    )

    // MARK: Destructive (experimental)

    static let deleteEmail = ToolHandler(
        tool: Tool(
            name: "delete_email",
            description: "[Experimental] Delete one or more messages by id. Irreversible.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Envelope ids to delete (at least one).")
                    ]),
                    "folder": folderProperty,
                    "account": accountProperty
                ]),
                "required": .array([.string("ids")])
            ])
        ),
        isExperimental: true,
        call: { params, application in
            let input = try decodeArguments(DeleteEmailRequest.Input.self, from: params.arguments)
            return try await DeleteEmailRequest().execute(input, in: application)
        }
    )

    /// Shared schema for an `attachments` argument: an array of absolute file paths.
    private static let attachmentsProperty: Value = .object([
        "type": .string("array"),
        "items": .object(["type": .string("string")]),
        "description": .string("Absolute paths of files to attach.")
    ])

    /// Builds an input schema with a single required `name` string plus optional `account`.
    private static func folderNameSchema(description: String) -> Value {
        .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string"),
                    "description": .string(description)
                ]),
                "account": accountProperty
            ]),
            "required": .array([.string("name")])
        ])
    }
}

/// Decodes MCP call arguments (`[String: Value]`) into a `Decodable` request
/// input by round-tripping through JSON — `Value` is `Codable`, so a missing
/// argument bag decodes the same as an empty object.
func decodeArguments<T: Decodable>(_ type: T.Type, from arguments: [String: Value]?) throws -> T {
    let data = try JSONEncoder().encode(arguments ?? [:])
    return try JSONDecoder().decode(T.self, from: data)
}
