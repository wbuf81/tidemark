import Foundation

/// The instruction a user pastes into Cowork so it logs each task for Tidemark.
public enum CoworkInstruction {
    /// `folderName` is the folder Cowork was given for the log; Tidemark reads `<folderName>/tidemark-log.jsonl`.
    public static func text(folderName: String = AppIdentity.coworkLogFolderName) -> String {
        """
        Keep a work log for Tidemark, my week calendar.

        When you finish a task, add one line to the file "\(folderName)/\(CoworkLogReader.jsonLinesName)", which is in the folder named "\(folderName)" that I have shared with you. Create the file if it is not there. Each line is one JSON object on its own line, with these fields:

        - "id": a short id for this task, letters, numbers, "-" and "_" only; use the same id for every turn of the same task
        - "start": when you began this turn, as an ISO 8601 time in UTC, like 2026-10-12T13:00:00Z
        - "end": when you finished it, in the same format
        - "title": 3 to 6 words naming the task
        - "ask": what I asked for, in under 150 characters
        - "folders": the names of the folders you worked in, up to 5
        - "scheduled": true when I did not start the task myself (a scheduled task); otherwise leave it out

        Example:
        {"id":"cse_Abc123","start":"2026-10-12T13:00:00Z","end":"2026-10-12T13:20:00Z","title":"Tide table fixes","ask":"fix the tide table","folders":["tide-tables"]}

        Rules:
        - Never let the log hold up or change the task. If the file cannot be written, carry on without it and do not mention it.
        - Skip turns where you used no tools, such as plain questions and answers.
        - Add to the file; never rewrite or delete earlier lines.
        - Do not put anything private in the log: no passwords, keys or personal details.
        """
    }
}
