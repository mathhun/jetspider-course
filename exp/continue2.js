i = 0
while (i < 3) {
    p(1);
    i = i + 1;
    if (i < 3) {
        p("continue");
        continue;
    } else {
        p("not continue");
    }
    p(2);
}
p(3);
