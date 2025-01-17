const std = @import("std");
const sqlite = @import("sqlite");

pub fn main() !void {
    // Initialize the SQLite database
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "test.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();

    // Create a table
    try db.exec("CREATE TABLE IF NOT EXISTS employees(id integer primary key, name text, age integer, salary integer)", .{}, .{});

    const query =
        \\INSERT INTO employees(name, age, salary) VALUES(?, ?, ?)
    ;

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    // Get standard input
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    while (true) {
        // Ask if user wants to add more employees
        try stdout.print("\nDo you want to add an employee? (y/n): ", .{});
        var response_buf: [4]u8 = undefined;
        if (try stdin.readUntilDelimiterOrEof(&response_buf, '\n')) |user_input| {
            if (std.mem.eql(u8, std.mem.trim(u8, user_input, &std.ascii.whitespace), "n")) {
                break;
            }
        }

        // Get employee name
        try stdout.print("Enter employee name: ", .{});
        var name_buf: [100]u8 = undefined;
        const name = (try stdin.readUntilDelimiterOrEof(&name_buf, '\n')) orelse break;
        const trimmed_name = std.mem.trim(u8, name, &std.ascii.whitespace);

        // Get employee age
        try stdout.print("Enter employee age: ", .{});
        var age_buf: [16]u8 = undefined;
        const age_input = (try stdin.readUntilDelimiterOrEof(&age_buf, '\n')) orelse break;
        const age = try std.fmt.parseInt(i64, std.mem.trim(u8, age_input, &std.ascii.whitespace), 10);

        // Get employee salary
        try stdout.print("Enter employee salary: ", .{});
        var salary_buf: [32]u8 = undefined;
        const salary_input = (try stdin.readUntilDelimiterOrEof(&salary_buf, '\n')) orelse break;
        const salary = try std.fmt.parseInt(i64, std.mem.trim(u8, salary_input, &std.ascii.whitespace), 10);

        // Insert the employee data
        try stmt.exec(.{}, .{
            .name = trimmed_name,
            .age = age,
            .salary = salary,
        });

        try stdout.print("Employee added successfully!\n", .{});
    }
}
