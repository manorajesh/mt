#include <ncurses.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <stdint.h>
#include <stdio.h>

#define NUM_PATTERNS 100
#define TEST_SECONDS 5

typedef struct {
    chtype ch;
    short fg;
    short bg;
} Cell;

int main(void) {
    initscr();
    noecho();
    cbreak();
    curs_set(0);
    start_color();
    use_default_colors();
    timeout(0); // Non-blocking input

    int height, width;
    getmaxyx(stdscr, height, width);

    if (can_change_color() && COLORS >= 256) {
        for (int i = 0; i < 256; i++) {
            init_pair(i + 1, i, (i + 128) % 256);
        }
    } else {
        for (int i = 0; i < 16; i++) {
            init_pair(i + 1, i % 8, (i + 4) % 8);
        }
    }

    const char glyphs[] = {'@', '#', '&', '*', '=', '%', 'Z', 'A'};
    const int glyphCount = sizeof(glyphs) / sizeof(glyphs[0]);

    srand((unsigned)time(NULL));
    static Cell ***patterns;

    // Allocate pattern buffer
    patterns = malloc(NUM_PATTERNS * sizeof(Cell **));
    for (int n = 0; n < NUM_PATTERNS; n++) {
        patterns[n] = malloc(height * sizeof(Cell *));
        for (int y = 0; y < height; y++) {
            patterns[n][y] = malloc(width * sizeof(Cell));
            for (int x = 0; x < width; x++) {
                patterns[n][y][x].ch = glyphs[rand() % glyphCount];
                patterns[n][y][x].fg = 1 + rand() % 16;
                patterns[n][y][x].bg = 1 + rand() % 16;
            }
        }
    }

    int frames = 0;
    clock_t start = clock();
    clock_t now;
    do {
        int index = frames % NUM_PATTERNS;
        erase();
        for (int y = 0; y < height; y++) {
            move(y, 0);
            for (int x = 0; x < width; x++) {
                int colorPair = (patterns[index][y][x].fg + patterns[index][y][x].bg) % 16 + 1;
                attron(COLOR_PAIR(colorPair));
                addch(patterns[index][y][x].ch);
                attroff(COLOR_PAIR(colorPair));
            }
        }
        refresh();
        frames++;

        now = clock();
        if (getch() == 27) break; // ESC to exit early
    } while (((double)(now - start) / CLOCKS_PER_SEC) < TEST_SECONDS);

    // Cleanup
    for (int n = 0; n < NUM_PATTERNS; n++) {
        for (int y = 0; y < height; y++) free(patterns[n][y]);
        free(patterns[n]);
    }
    free(patterns);

    erase();
    refresh();
    endwin();

    double seconds = (double)(now - start) / CLOCKS_PER_SEC;
    int fps = (int)(frames / seconds);

    printf("------ RESULTS ------\n");
    printf("FPS: %d\n", fps);

    // Save to file
    FILE *out = fopen("stress_results.txt", "w");
    if (out) {
        fprintf(out, "------ RESULTS ------\nFPS: %d\n", fps);
        fclose(out);
    } else {
        fprintf(stderr, "Failed to write to stress_results.txt\n");
    }

    return 0;
}

