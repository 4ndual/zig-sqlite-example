const std = @import("std");
const sqlite = @import("sqlite");

// Function to display the menu
fn displayMenu(writer: anytype) !void {
    try writer.print("\n=== Employee Management System ===\n", .{});
    try writer.print("1. Add Employee\n", .{});
    try writer.print("2. Update Employee\n", .{});
    try writer.print("3. Delete Employee\n", .{});
    try writer.print("4. Exit\n", .{});
    try writer.print("Enter your choice (1-4): ", .{});
}

fn readLine(reader: anytype, buffer: []u8) !?[]const u8 {
    @memset(buffer, 0);
    const line = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return null;
    if (line.len > 0 and line[line.len - 1] == '\r') {
        return std.mem.trim(u8, line[0 .. line.len - 1], &std.ascii.whitespace);
    }
    return std.mem.trim(u8, line, &std.ascii.whitespace);
}

pub fn main() !void {
    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = "test.db" },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    defer db.deinit();

    try db.exec("CREATE TABLE IF NOT EXISTS employees(id integer primary key, name text, age integer, salary integer)", .{}, .{});

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    // Separate buffers for different inputs
    var choice_buffer: [16]u8 = undefined;
    var id_buffer: [16]u8 = undefined;
    var name_buffer: [100]u8 = undefined;
    var age_buffer: [16]u8 = undefined;
    var salary_buffer: [32]u8 = undefined;

    while (true) {
        try displayMenu(stdout);

        if (try readLine(stdin, &choice_buffer)) |choice_input| {
            const choice = std.fmt.parseInt(u8, choice_input, 10) catch {
                try stdout.print("Invalid input. Please enter a number between 1 and 4.\n", .{});
                continue;
            };

            switch (choice) {
                1 => { // Add Employee
                    var stmt = try db.prepare("INSERT INTO employees(name, age, salary) VALUES(?1, ?2, ?3)");
                    defer stmt.deinit();

                    try stdout.print("Enter employee name: ", .{});
                    const name = (try readLine(stdin, &name_buffer)) orelse break;
                    if (name.len == 0) {
                        try stdout.print("Name cannot be empty.\n", .{});
                        continue;
                    }

                    try stdout.print("Enter employee age: ", .{});
                    const age_input = (try readLine(stdin, &age_buffer)) orelse break;
                    const age = std.fmt.parseInt(i64, age_input, 10) catch {
                        try stdout.print("Invalid age format.\n", .{});
                        continue;
                    };

                    try stdout.print("Enter employee salary: ", .{});
                    const salary_input = (try readLine(stdin, &salary_buffer)) orelse break;
                    const salary = std.fmt.parseInt(i64, salary_input, 10) catch {
                        try stdout.print("Invalid salary format.\n", .{});
                        continue;
                    };

                    try stmt.exec(.{}, .{ name, age, salary });
                    try stdout.print("Employee added successfully!\n", .{});
                },
                2 => { // Update Employee
                    try stdout.print("\nEnter employee ID to update: ", .{});
                    const id_input = (try readLine(stdin, &id_buffer)) orelse break;
                    const id = std.fmt.parseInt(i64, id_input, 10) catch {
                        try stdout.print("Invalid ID format.\n", .{});
                        continue;
                    };

                    try stdout.print("Enter new name (or press enter to skip): ", .{});
                    const name = (try readLine(stdin, &name_buffer)) orelse break;

                    try stdout.print("Enter new age (or 0 to skip): ", .{});
                    const age_input = (try readLine(stdin, &age_buffer)) orelse break;
                    const age = std.fmt.parseInt(i64, age_input, 10) catch {
                        try stdout.print("Invalid age format.\n", .{});
                        continue;
                    };

                    try stdout.print("Enter new salary (or 0 to skip): ", .{});
                    const salary_input = (try readLine(stdin, &salary_buffer)) orelse break;
                    const salary = std.fmt.parseInt(i64, salary_input, 10) catch {
                        try stdout.print("Invalid salary format.\n", .{});
                        continue;
                    };

                    // Debug print before update
                    try stdout.print("Debug - About to update ID {}: name='{s}', age={}, salary={}\n", .{ id, name, age, salary });

                    if (name.len > 0) {
                        var stmt = try db.prepare("UPDATE employees SET name = ?1 WHERE id = ?2");
                        defer stmt.deinit();
                        try stmt.exec(.{}, .{ name, id });
                        try stdout.print("Name updated.\n", .{});
                    }

                    if (age > 0) {
                        var stmt = try db.prepare("UPDATE employees SET age = ?1 WHERE id = ?2");
                        defer stmt.deinit();
                        try stmt.exec(.{}, .{ age, id });
                        try stdout.print("Age updated.\n", .{});
                    }

                    if (salary > 0) {
                        var stmt = try db.prepare("UPDATE employees SET salary = ?1 WHERE id = ?2");
                        defer stmt.deinit();
                        try stmt.exec(.{}, .{ salary, id });
                        try stdout.print("Salary updated.\n", .{});
                    }

                    if (name.len == 0 and age == 0 and salary == 0) {
                        try stdout.print("No fields to update!\n", .{});
                        continue;
                    }

                    try stdout.print("Employee update completed!\n", .{});
                },
                3 => { // Delete Employee
                    try stdout.print("\nEnter employee ID to delete: ", .{});
                    const id_input = (try readLine(stdin, &id_buffer)) orelse break;
                    const id = std.fmt.parseInt(i64, id_input, 10) catch {
                        try stdout.print("Invalid ID format.\n", .{});
                        continue;
                    };

                    var stmt = try db.prepare("DELETE FROM employees WHERE id = ?1");
                    defer stmt.deinit();

                    try stmt.exec(.{}, .{id});
                    try stdout.print("Employee deleted successfully!\n", .{});
                },
                4 => break,
                else => try stdout.print("Invalid choice. Please enter a number between 1 and 4.\n", .{}),
            }
        } else {
            break;
        }
    }
}
