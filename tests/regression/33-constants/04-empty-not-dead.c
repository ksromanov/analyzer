//PARAM: --set ana.activated '["constants"]'

int g;

int main() {
    // state: {bot}, because no locals
    g = 1; // state: {bot}, because Hoare set add (in PathSensitive2 map) keeps bot, while reduce would remove
    return 0;
}
