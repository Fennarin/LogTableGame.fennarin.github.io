using Gtk;

// Spacing used for most things.
const int SPACING = 8;
// Minimum number of significant digits in answers.
const int MIN_SIGNIFICANT = 3;

// Global definitions.
Window window;
Stack pages;
GameBox game_box;
MainMenu main_menu;
int range_min;
int range_max;
enum Mode { NORMAL, SHUFFLED, REVERSE }
Mode mode = NORMAL;

// Returns the log argument for a particular index.
string argument_from_index(int i) {
	return @"$(1+i/100).$(i/10%10)$(i%10)";
}
// Rounds to the nearest integer.
int round_to_int(double x) {
  return (int)(x < 0 ? x - 0.5 : x + 0.5);
}
// Returns current settings as a colored string.
string settings_to_string() {
	var mode_name = mode == NORMAL ? "normal" : mode == SHUFFLED ? "shuffled" : "reverse";
	return span(@"$(argument_from_index(range_min)) to $(argument_from_index(range_max)), $mode_name mode", INFO);
}
// Select game mode using radio buttons.
void connect_radio_button(CheckButton radio, Mode new_mode) {
	radio.toggled.connect(() => { if (radio.active) mode = new_mode; });
}
// Add a margin to a widget.
void set_default_margin(Widget widget) {
	widget.margin_top = SPACING;
	widget.margin_bottom = SPACING;
	widget.margin_start = SPACING;
	widget.margin_end = SPACING;
}
// Show a basic alert dialog.
void show_alert(string message) {
	var dialog = new AlertDialog(message);
	dialog.set_modal(true);
	dialog.show(window);
}

// Color module.
enum Color { GOOD, WARN, BAD, INFO, DEFAULT }

const string[] dark_theme = {"#5CFF8E", "#FFD85C", "#FF7070", "#66A3FF"};
const string[] light_theme = {"#166D32", "#966A00", "#B02020", "#1A4FA3"};

bool is_dark_theme() {
	// Get default foreground color.
	var color = window.get_color();
	// If luminance of foreground color is more than 50%, it's probably a dark theme.
	return 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue > 0.5;
}
string get_color(Color color) {
	return is_dark_theme() ? dark_theme[(int)color] : light_theme[(int)color];
}
string span(string message, Color color) {
	return color == DEFAULT ? message : @"<span foreground='$(get_color(color))'>$message</span>";
}

// Base class for custom dialogs.
class CustomDialog : Window {
	const string[] DEFAULT_OPTIONS = {"Close"};

	protected Box box;
	protected Label[] labels;
	protected Button[] buttons;

	protected void init_custom_dialog(string title, string[] message_lines, string[]? options = null, int cancel_option = 0) {
		this.title = title;
		resizable = false;
		modal = true;
		set_transient_for(window);

		box = new Box(VERTICAL, SPACING) { valign = CENTER };
		set_default_margin(box);

		labels = new Label[message_lines.length];
		for (int i = 0; i < message_lines.length; ++i) {
			box.append(labels[i] = new Label(message_lines[i]));
		}

		options = options ?? DEFAULT_OPTIONS;
		var box_controls = new Box(HORIZONTAL, SPACING);
		buttons = new Button[options.length];
		for (int i = 0; i < options.length; ++i) {
			box_controls.append(buttons[i] = new Button.with_label(options[i]) { hexpand = true });
		}
		box.append(box_controls);

		buttons[cancel_option].clicked.connect(close);

		child = box;
	}

	protected delegate void Callback();
	protected void set_callback(int button_id, Callback callback) {
		buttons[button_id].clicked.connect(() => {
			callback();
			close();
		});
	}
}

// A dialog explaining how to play.
class HowToPlayDialog : CustomDialog {
	public HowToPlayDialog() {
		string[] message_lines = new string[mode == NORMAL ? 1 : 2];
		message_lines[0] =
"""Try to guess the logarithm with %s
After typing your answer, press enter to continue.
If you make a mistake, the correct answer will be shown in %s
After answering all questions, you can retry the ones you got wrong.""".printf(
			span(@"at least $MIN_SIGNIFICANT significant digits of accuracy.", GOOD),
			span("yellow.", WARN));
		
		if (mode == SHUFFLED) message_lines[1] = @"$(span("Shuffled mode:", INFO)) questions appear in random order.";
		else if (mode == REVERSE) message_lines[1] = @"$(span("Reverse mode:", INFO)) guess what number the logarithm is of.";

		init_custom_dialog("How to play", message_lines);
		foreach (var label in labels) label.set_use_markup(true);
	}
}

// A dialog for restarting the game, or returning to the main menu.
class PlayDialog : CustomDialog {
	public PlayDialog() {
		init_custom_dialog(
			"Settings", {
				"Are these settings correct?",
				settings_to_string()
			},
			{"Play", "Cancel"}, 1
		);
		labels[1].set_use_markup(true);
		set_callback(0, game_box.play);
	}
}

// A dialog for restarting the game, or returning to the main menu.
class RestartDialog : CustomDialog {
	public RestartDialog() {
		init_custom_dialog(
			"Restart game", {
				"Play again with the following settings?",
				settings_to_string()
			},
			{"Yes", "Cancel", "Change settings"}, 1
		);
		labels[1].set_use_markup(true);
		set_callback(0, game_box.play);
		set_callback(2, main_menu.present);
	}
}

// A dialog for quitting the game, or returning to the main menu.
class QuitDialog : CustomDialog {
	public QuitDialog() {
		init_custom_dialog(
			"Quit game", {"Are you sure you want to quit?"},
			{"Yes", "Cancel", "Main menu"}, 1
		);
		set_callback(0, window.close);
		set_callback(2, main_menu.present);
	}
}

// A scrollable history of answers, along with a text field to query the user.
// Add AnswerList.scroll_view to your container, not AnswerList itself.
class AnswerList : Grid {
	public class Row {
		public Label left;
		public Label middle;
		public Label right;

		public Row() {
			left = new Label(null) { use_markup = true, halign = END, xalign = 1 };
			middle = new Label(null) { use_markup = true, halign = CENTER, xalign = 0.5f };
			right = new Label(null) { use_markup = true, halign = START, xalign = 0 };
		}

		public void copy(Row other) {
			left.label = other.left.label;
			middle.label = other.middle.label;
			right.label = other.right.label;
		}
		public void set_label(string text, Color color = DEFAULT) {
			int equals_sign_index = text.index_of("=");
			if (equals_sign_index != -1) {
				left.label = span(text[0:equals_sign_index], color);
				middle.label = span("=", color);
				right.label = span(text[equals_sign_index+1:text.length], color);
			} else {
				left.label = span(text, color);
				middle.label = "";
				right.label = "";
			}
		}
	}

	const int MAX_HISTORY = 100;
	const int VIEW_HEIGHT = 76;

	Row history[MAX_HISTORY];
	int history_length;
	int scroll_queued;
	bool query_attached;
	bool finished_attached;
	Label size_tagged;
	Adjustment scroll_adjustment;
	Box box_query;

	public ScrolledWindow scroll_view;
	public Row label_query;
	public Text text_query;
	public string current_query;

	public AnswerList() {
		halign = CENTER;
		valign = END;

		history_length = 0;
		scroll_queued = 0;
		query_attached = false;
		finished_attached = false;
		size_tagged = null;

		scroll_view = new ScrolledWindow() {
			min_content_height = VIEW_HEIGHT,
			hscrollbar_policy = NEVER,
			vscrollbar_policy = AUTOMATIC,
			child = this
		};
		scroll_adjustment = scroll_view.vadjustment;

		label_query = new Row();
		attach(label_query.left, 0, history_length);
		attach(label_query.middle, 1, history_length);
		box_query = new Box(HORIZONTAL, 0);
		box_query.append(label_query.right);
		box_query.append(text_query = new Text() { max_width_chars = 7 });
		attach(box_query, 2, history_length);
	}

	public void clear() {
		for (int i = 0; i < history_length; ++i) remove_row(0);
		history_length = 0;
	}
	public void push(string new_item, Color color) {
		if (history_length < MAX_HISTORY) {
			insert_row(history_length);
			if (history[history_length] == null) {
				history[history_length] = new Row();
			}
			attach_row(history[history_length], history_length);
			++history_length;
			if (history_length > 0) {
				queue_scroll_to_bottom();
			}
		} else {
			for (int i = 1; i < history_length; ++i) {
				history[i - 1].copy(history[i]);
			}
		}
		history[history_length - 1].set_label(new_item, color);
	}

	public void set_query(string? query) {
		label_query.set_label(current_query = query);
	}
	public void set_query_visible(bool visible) {
		if (history_length > 0) {
			// Reset previous size request.
			if (size_tagged != null) size_tagged.set_size_request(-1, -1);
			// When hiding the query, set a label to the desired size of the query box to keep the grid aligned.
			if (!visible) {
				int minimum, natural, minimum_baseline, natural_baseline;
				box_query.measure(HORIZONTAL, 100, out minimum, out natural, out minimum_baseline, out natural_baseline);
				(size_tagged = history[history_length - 1].right).set_size_request(natural, -1);
			}
		}
		label_query.left.set_visible(visible);
		label_query.middle.set_visible(visible);
		label_query.right.set_visible(visible);
		box_query.set_visible(visible);
	}

	public void scroll_to_bottom() {
		scroll_adjustment.value = scroll_adjustment.upper - VIEW_HEIGHT;
	}
	public void queue_scroll_to_bottom() {
		// Attempt scrolling right away for good measure.
		scroll_to_bottom();

		bool already_queued = scroll_queued > 0;
		scroll_queued = 16; // Set maximum number of ticks to wait for size change.
		if (already_queued) return;
		
		var previous_height = scroll_adjustment.upper;
		add_tick_callback(() => {
			// Repeat until size has actually updated, then scroll to bottom.
			if (scroll_adjustment.upper == previous_height && --scroll_queued > 0) return true;
			scroll_to_bottom();
			scroll_queued = 0;
			return false;
		});
	}

	void attach_row(Row row, int row_index) {
		attach(row.left, 0, row_index);
		attach(row.middle, 1, row_index);
		attach(row.right, 2, row_index);
	}
}

// Page where the game takes place.
class GameBox : Box {
	int query_order[100];
	bool answered[100];
	int num_queries;
	int num_remaining;
	int num_mistakes;
	int query_index;
	string correct_answer;
	
	Label label_status;
	AnswerList answer_list;
	Text text_query;
	Label label_finished;
	bool label_finished_shown;
	
	public GameBox() {
		orientation = VERTICAL;
		spacing = SPACING;
		valign = END;

		label_status = new Label(null);
		label_status.set_use_markup(true);

		answer_list = new AnswerList();
		text_query = answer_list.text_query;
		text_query.activate.connect(validate_query);
		text_query.changed.connect(answer_list.scroll_to_bottom);

		label_finished = new Label(null);
		label_finished.set_use_markup(true);
		label_finished_shown = false;

		var button_restart = new Button.with_label("Restart") { hexpand = true };
		var button_how_to_play = new Button.with_label("How to play") { hexpand = true };
		var button_quit = new Button.with_label("Quit") { hexpand = true };
		button_restart.clicked.connect(() => { new RestartDialog().present(); });
		button_how_to_play.clicked.connect(() => { new HowToPlayDialog().present(); });
		button_quit.clicked.connect(() => ( new QuitDialog().present() ));

		var box_controls = new Box(HORIZONTAL, SPACING);
		box_controls.append(button_restart);
		box_controls.append(button_how_to_play);
		box_controls.append(button_quit);

		append(label_status);
		append(answer_list.scroll_view);
		append(box_controls);
	}

	public void play() {
		num_mistakes = 0;
		// Prepare list of queries.
		num_queries = 0;
		for (int x = range_min; x <= range_max; ++x, ++num_queries) {
			query_order[num_queries] = x;
			answered[num_queries] = false;
		}
		num_remaining = num_queries;
		if (mode != NORMAL) shuffle_order();
		// Start at first query.
		query_index = 0;
		answer_list.clear();
		next_query();
		hide_finished_label();
		show_query();
		pages.set_visible_child(this);
	}

	void finish_game() {
		hide_query();
		var mistakes_span = span(num_mistakes.to_string(), num_mistakes == 0 ? Color.GOOD : num_mistakes < num_queries ? Color.WARN : Color.BAD);
		show_finished_label(@"Finished with $mistakes_span mistake$(num_mistakes == 1 ? "" : "s") in total.");
		label_status.label = "All questions answered!";
	}

	// Helper functions to show/hide sections.
	public void hide_finished_label() {
		if (label_finished_shown) {
			remove(label_finished);
			label_finished_shown = false;
		}
	}
	public void show_finished_label(string text) {
		label_finished.label = text;
		if (!label_finished_shown) {
			insert_child_after(label_finished, answer_list.scroll_view);
			label_finished_shown = true;
		}
	}
	public void hide_query() { answer_list.set_query_visible(false); }
	public void show_query() { answer_list.set_query_visible(true); }

	// Prompt user with next query, or finish if none are left.
	void next_query() {
		// While retrying, skip questions that were already answered correctly.
		while (query_index < num_queries && answered[query_index]) ++query_index;
		if (query_index >= num_queries) {
			if (num_remaining <= 0) {
				finish_game();
				return;
			}
			// Give user time to review before retrying.
			hide_query();
			show_finished_label(span(@"$num_remaining incorrect", WARN) + ", retrying...");
			Timeout.add_once(1000, () => {
				answer_list.clear();
				query_index = 0;
				next_query();
				hide_finished_label();
				show_query();
			});
		}
		var status_header = (num_mistakes < num_remaining) ? @"Questions remaining" : @"$(span("Retrying", WARN)) questions";
		label_status.label = @"$status_header: $num_remaining";
		int i = query_order[query_index++];
		var argument = argument_from_index(i);
		var logarithm = Math.log10(1.0 + i / 100.0).to_string();
		if (mode == REVERSE) {
			correct_answer = argument;
			answer_list.set_query(@"$(round_answer(logarithm)) = log<b><sub>10</sub></b> of ");
			text_query.text = i < 100 ? "1." : "2.";
		} else {
			correct_answer = logarithm;
			answer_list.set_query(@"log<b><sub>10</sub></b>($argument) = ");
			text_query.text = "0.";
		}
		text_query.grab_focus();
		text_query.set_position(-1);
	}

	void validate_query() {
		if (validate_answer(text_query.text.strip(), correct_answer)) {
			answered[query_index - 1] = true;
			--num_remaining;
			answer_list.push(@"$(answer_list.current_query)$(text_query.text)", GOOD);
		} else {
			++num_mistakes;
			answer_list.push(@"$(answer_list.current_query)$(round_answer(correct_answer))", WARN);
		}
		next_query();
	}

	void shuffle_order() {
		// Fisher-Yates shuffle
		for (int i = num_queries - 1; i > 0; --i) {
			int j = Random.int_range(0, i + 1);
			if (i != j) {
				int _swap = query_order[j];
				query_order[j] = query_order[i];
				query_order[i] = _swap;
			}
		}
	}

	// Gets the digit at index i, skipping the decimal point, padded with trailing zeroes if exceeding length.
	static char digit_at(string number, int i, int decimal_point) {
		i += (int)(i >= decimal_point);
		return i < number.length ? number[i] : '0';
	}

	static bool validate_answer(owned string input, string correct) {
		int input_decimal_point = input.index_of(".");
		int correct_decimal_point = correct.index_of(".");
		int input_length = input.length;
		// Implicitly put decimal point at end of number if there is none, and don't count it in the length if there is one.
		if (input_decimal_point == -1) input_decimal_point = input_length;
		else if (input_decimal_point == 0) { // Starting with the decimal is equivalent to starting wtih "0.".
			input = "0" + input;
			input_decimal_point = 1;
		} else --input_length;
		if (correct_decimal_point == -1) correct_decimal_point = correct.length;
		// Decimal point must be at the same index.
		if (input_decimal_point != correct_decimal_point) return false;
		// Iterate to last significant digit, but at least the minimum, unless all zeroes.
		int i = 0;
		int num_significant = 0;
		while (i < input_length || (num_significant > 0 && num_significant < MIN_SIGNIFICANT)) {
			char digit = digit_at(input, i++, input_decimal_point);
			num_significant += (int)(digit >= '0' && digit <= '9' && (digit >= '1' || num_significant > 0));
		}
		// If the input is all zeroes, check the entire correct answer to see if it's also all zeroes.
		if (num_significant == 0) i = correct.length;
		// i is now the index following the last significant digit of the input.
		// Round the last digit of the correct answer to match the input length.
		bool carry = digit_at(correct, i, correct_decimal_point) >= '5';
		while (--i >= 0) {
			char correct_digit = digit_at(correct, i, correct_decimal_point);
			char input_digit = digit_at(input, i, input_decimal_point);
			if (carry = (correct_digit += (char)carry) > '9') correct_digit = '0';
			if (input_digit != correct_digit) return false;
		}
		return true;
	}

	static string round_answer(string answer) {
		int i = 0;
		int num_significant = 0;
		while (i < answer.length && num_significant < MIN_SIGNIFICANT) {
			char digit = answer[i++];
			num_significant += (int)(digit >= '0' && digit <= '9' && (digit >= '1' || num_significant > 0));
		}
		int desired_length = i;
		bool carry = i < answer.length && answer[i] >= '5';
		var rounded = answer.to_utf8();
		while (--i >= 0) {
			var digit = rounded[i];
			if (digit >= '0' && digit <= '9' && (carry = (rounded[i] += (char)carry) > '9')) rounded[i] = '0';
			// Remove trailing zeroes.
			if (i == desired_length - 1 && rounded[i] == '0') --desired_length;
		}
		// Null-terminate the string to shorten it.
		if (desired_length < answer.length) rounded[desired_length] = 0;
		return (string) rounded;
	}
}

// Main menu page. Settings can be changed here.
class MainMenu : Box {
	class RangeEntry : Entry {
		public RangeEntry(string default_text, float alignment = 0) {
			text = default_text;
			width_chars = 4;
			max_width_chars = 4;
			xalign = alignment;
		}
	}
	RangeEntry entry_range_min;
	RangeEntry entry_range_max;
	
	public MainMenu() {
		orientation = VERTICAL;
		spacing = SPACING;
		valign = CENTER;
		
		var button_play = new Button.with_label("Play");
		button_play.clicked.connect(parse_settings_and_play);
		
		var box_range = new Box(HORIZONTAL, SPACING) { halign = CENTER };
		box_range.append(new Label("Question range:"));
		box_range.append(entry_range_min = new RangeEntry("1.01", 1));
		box_range.append(new Label("to"));
		box_range.append(entry_range_max = new RangeEntry("2.00"));
		entry_range_min.activate.connect(parse_settings_and_play);
		entry_range_max.activate.connect(parse_settings_and_play);
		
		var radio_normal = new CheckButton.with_label("Normal");
		var radio_shuffled = new CheckButton.with_label("Shuffled");
		var radio_reverse = new CheckButton.with_label("Reverse");
		radio_shuffled.set_group(radio_normal);
		radio_reverse.set_group(radio_normal);
		radio_normal.active = true;
		connect_radio_button(radio_normal, NORMAL);
		connect_radio_button(radio_shuffled, SHUFFLED);
		connect_radio_button(radio_reverse, REVERSE);

		var box_modes = new Box(HORIZONTAL, 0) { halign = CENTER };
		box_modes.append(radio_normal);
		box_modes.append(radio_shuffled);
		box_modes.append(radio_reverse);
		
		var button_exit = new Button.with_label("Exit");
		button_exit.clicked.connect(() => { window.close(); });
		append(button_play);
		append(box_range);
		append(box_modes);
		append(button_exit);
	}
	
	public void parse_settings_and_play() {
		// Convert decimal notation to integer range.
		range_min = round_to_int((double.parse(entry_range_min.text) - 1) * 100);
		range_max = round_to_int((double.parse(entry_range_max.text) - 1) * 100);
		if (range_min < 1 || range_min > 100 || range_max < 1 || range_max > 100) {
			show_alert("Range must be between 1.01 and 2.00.");
			return;
		}
		if (range_min > range_max) {
			var _swap = range_min;
			range_min = range_max;
			range_max = _swap;
		}

		new PlayDialog().present();
	}

	public void present() {
		// Shrink game box back to default size before returning to main menu.
		game_box.hide_finished_label();
		pages.set_visible_child(this);
	}
}

class MainApp : Gtk.Application {

	public MainApp() {
		Object(application_id: "io.github.fennarin.LogTableGame");
		Window.set_default_icon_name("log-table-game-icon");
	}
	
	public override void activate() {
		window = new ApplicationWindow(this) {
			title = "Log Table Game",
			resizable = false
		};

		main_menu = new MainMenu();
		game_box = new GameBox();
		
        pages = new Stack();
		set_default_margin(pages);
		pages.add_child(main_menu);
		pages.add_child(game_box);
        window.child = pages;
		window.present();
	}
}

int main(string[] args) {
	return new MainApp().run(args);
}
