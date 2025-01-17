const std = @import("std");
const sqlite = @import("sqlite");
const json = std.json;

const Employee = struct {
    id: i64,
    name: [100:0]u8,
    age: i64,
    salary: i64,
};

fn displayMenu(writer: anytype) !void {
    try writer.print("\n=== Employee Management System ===\n", .{});
    try writer.print("1. Add Employee\n", .{});
    try writer.print("2. View Employees\n", .{});
    try writer.print("3. Update Employee\n", .{});
    try writer.print("4. Delete Employee\n", .{});
    try writer.print("5. Import Employees from JSON\n", .{});
    try writer.print("6. Exit\n", .{});
    try writer.print("Enter your choice (1-6): ", .{});
}

fn importEmployeesFromJson(db: *sqlite.Db, allocator: std.mem.Allocator, filename: []const u8) !usize {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, try file.getEndPos());
    defer allocator.free(content);

    std.debug.print("Reading JSON content:\n{s}\n", .{content});

    var parsed_value = try std.json.parseFromSlice(
        json.Value,
        allocator,
        content,
        .{},
    );
    defer parsed_value.deinit();

    if (parsed_value.value != .array) {
        std.debug.print("Error: Expected array at root\n", .{});
        return error.InvalidJsonFormat;
    }

    try db.exec("BEGIN TRANSACTION", .{}, .{});

    const query =
        \\INSERT INTO employees(name, age, salary) 
        \\VALUES (?, ?, ?)
    ;

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    var count: usize = 0;

    for (parsed_value.value.array.items) |item| {
        if (item != .object) continue;
        const obj = item.object;

        const name = obj.get("name") orelse continue;
        const age = obj.get("age") orelse continue;
        const salary = obj.get("salary") orelse continue;

        if (name != .string or age != .integer or salary != .integer) continue;
        if (name.string.len >= 100) {
            std.debug.print("Warning: Name too long: {s}\n", .{name.string});
            continue;
        }

        stmt.reset();
        try stmt.exec(.{}, .{ name.string, @as(i64, age.integer), @as(i64, salary.integer) });

        count += 1;
        std.debug.print("Inserted: name={s}, age={d}, salary={d}\n", .{
            name.string,
            age.integer,
            salary.integer,
        });
    }

    try db.exec("COMMIT", .{}, .{});

    return count;
}
fn readLine(reader: anytype, buffer: []u8) !?[]const u8 {
    @memset(buffer, 0);
    const line = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return null;
    if (line.len > 0 and line[line.len - 1] == '\r') {
        return std.mem.trim(u8, line[0 .. line.len - 1], &std.ascii.whitespace);
    }
    return std.mem.trim(u8, line, &std.ascii.whitespace);
}

fn displayEmployees(db: *sqlite.Db, writer: anytype) !void {
    var stmt = try db.prepare("SELECT id, name, age, salary FROM employees ORDER BY id");
    defer stmt.deinit();

    try writer.print("\n{s: <5} {s: <20} {s: <8} {s: <10}\n", .{ "ID", "Name", "Age", "Salary" });
    try writer.print("{s}\n", .{"-" ** 45});

    var iter = try stmt.iterator(Employee, .{});

    while (try iter.next(.{})) |employee| {
        const name = std.mem.span(@as([*:0]const u8, &employee.name));
        try writer.print("{d: <5} {s: <20} {d: <8} {d: <10}\n", .{ employee.id, name, employee.age, employee.salary });
    }
    try writer.print("\n", .{});
}

fn getEmployee(db: *sqlite.Db, id: i64) !?Employee {
    var stmt = try db.prepare("SELECT id, name, age, salary FROM employees WHERE id = ?1");
    defer stmt.deinit();

    return try stmt.one(Employee, .{}, .{id});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
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
    var filename_buffer: [256]u8 = undefined;

    while (true) {
        try displayMenu(stdout);

        if (try readLine(stdin, &choice_buffer)) |choice_input| {
            const choice = std.fmt.parseInt(u8, choice_input, 10) catch {
                try stdout.print("Invalid input. Please enter a number between 1 and 5.\n", .{});
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
                2 => { // View Employees
                    try displayEmployees(&db, stdout);
                },
                3 => { // Update Employee
                    try displayEmployees(&db, stdout);

                    try stdout.print("\nEnter employee ID to update: ", .{});
                    const id_input = (try readLine(stdin, &id_buffer)) orelse break;
                    const id = std.fmt.parseInt(i64, id_input, 10) catch {
                        try stdout.print("Invalid ID format.\n", .{});
                        continue;
                    };

                    // First check if employee exists
                    if (try getEmployee(&db, id)) |_| {
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
                    } else {
                        try stdout.print("Employee not found!\n", .{});
                    }
                },
                4 => { // Delete Employee
                    try displayEmployees(&db, stdout);

                    try stdout.print("\nEnter employee ID to delete: ", .{});
                    const id_input = (try readLine(stdin, &id_buffer)) orelse break;
                    const id = std.fmt.parseInt(i64, id_input, 10) catch {
                        try stdout.print("Invalid ID format.\n", .{});
                        continue;
                    };

                    if (try getEmployee(&db, id)) |_| {
                        var stmt = try db.prepare("DELETE FROM employees WHERE id = ?1");
                        defer stmt.deinit();

                        try stmt.exec(.{}, .{id});
                        try stdout.print("Employee deleted successfully!\n", .{});
                    } else {
                        try stdout.print("Employee not found!\n", .{});
                    }
                },
                5 => { // Import from JSON
                    try stdout.print("Enter JSON file path: ", .{});
                    const filename = (try readLine(stdin, &filename_buffer)) orelse break;

                    const imported_count = importEmployeesFromJson(&db, allocator, filename) catch |err| {
                        switch (err) {
                            error.FileNotFound => try stdout.print("File not found: {s}\n", .{filename}),
                            error.InvalidCharacter, error.UnexpectedEndOfInput => try stdout.print("Invalid JSON format in file: {s}\n", .{filename}),
                            else => try stdout.print("Error importing data: {any}\n", .{err}),
                        }
                        continue;
                    };

                    try stdout.print("Successfully imported {d} employees from JSON.\n", .{imported_count});
                },
                6 => break,
                else => try stdout.print("Invalid choice. Please enter a number between 1 and 5.\n", .{}),
            }
        } else {
            break;
        }
    }
}
