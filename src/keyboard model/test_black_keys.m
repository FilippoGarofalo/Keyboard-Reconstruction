% =========================================================================
% TEST: virtual keyboard with black keys
%   1. Loads the existing H_white_calibration.mat
%   2. Builds the unified virtual keyboard (52 white + 36 black)
%   3. Visualises both layers on top of the rectified image
%   4. Verifies map_point_to_key on a few known coordinates
% =========================================================================

close all; clear; clc;

repoRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(repoRoot, 'homography_white'));
addpath(fullfile(repoRoot, 'virtual_keyboard'));
addpath(fullfile(repoRoot, 'mapping'));

%% 1. Load calibration
calibFile = fullfile(repoRoot, 'H_white_calibration.mat');
if ~isfile(calibFile)
    error('Calibrazione non trovata: %s\nLancia prima test.m', calibFile);
end
data = load(calibFile);
calibration = data.calibration;

%% 2. Build the full virtual keyboard
% Nota di partenza: prima nota bianca visibile a sinistra nel video.
% Se la calibrazione contiene il campo .firstVisibleNote (calibrazioni
% nuove), build_virtual_keyboard lo usa in automatico. Qui forziamo 'F'
% per essere robusti anche con .mat vecchi privi del campo.
START_NOTE = 'C';
virtualKeyboard = build_virtual_keyboard(calibration, 'StartNote', START_NOTE);

numWhite = numel(virtualKeyboard.whiteKeys);
numBlack = virtualKeyboard.numBlackKeys;
fprintf('Tasti bianchi : %d\n', numWhite);
fprintf('Tasti neri    : %d\n', numBlack);
fprintf('Tasti totali  : %d\n', numel(virtualKeyboard.allKeys));

% Numero di neri atteso, derivato dal pattern d'ottava e dalla startNote.
constants = keyboard_constants();
letters = 'CDEFGAB';
startIdx = strfind(letters, upper(virtualKeyboard.startNote(1)));
rotatedPattern = circshift(constants.octavePattern, -(startIdx - 1));
reps = ceil((numWhite - 1) / 7);
hasBlackAfter = repmat(rotatedPattern, 1, reps);
hasBlackAfter = hasBlackAfter(1:numWhite - 1);
expectedBlacks = sum(hasBlackAfter);

assert(numBlack == expectedBlacks, ...
    'Attesi %d neri per %d bianchi da %s, trovati %d', ...
    expectedBlacks, numWhite, virtualKeyboard.startNote, numBlack);

if numWhite ~= 52
    warning(['Il .mat è calibrato per %d tasti bianchi, non 52. ' ...
             'Test del pattern OK, ma la geometria non corrisponde ' ...
             'a un pianoforte 88-tasti completo.'], numWhite);
end

%% 3. Visualise on the rectified image
figure('Name', 'Virtual Keyboard - White + Black');
imshow(calibration.rectifiedImage); hold on;

% Bianchi: contorni verdi
for k = 1:numel(virtualKeyboard.whiteKeys)
    poly = virtualKeyboard.whiteKeys(k).polygonPx;
    plot(poly([1:4, 1], 1), poly([1:4, 1], 2), 'g-', 'LineWidth', 1);
end

% Neri: poligoni rossi semitrasparenti
for k = 1:numel(virtualKeyboard.blackKeys)
    poly = virtualKeyboard.blackKeys(k).polygonPx;
    patch('XData', poly(:, 1), 'YData', poly(:, 2), ...
          'FaceColor', 'r', 'FaceAlpha', 0.35, ...
          'EdgeColor', 'r', 'LineWidth', 1.2);
    % Etichetta indice nero
    cx = virtualKeyboard.blackKeys(k).centerPx(1);
    cy = virtualKeyboard.blackKeys(k).centerPx(2);
    text(cx, cy, sprintf('%d', virtualKeyboard.blackKeys(k).index), ...
        'Color', 'w', 'FontSize', 7, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center');
end

title(sprintf('Virtual Keyboard — %d white + %d black', ...
    numel(virtualKeyboard.whiteKeys), virtualKeyboard.numBlackKeys));
hold off;

%% 4. Numerical checks on map_point_to_key
% Test agnostici rispetto a startNote: i punti sono derivati dal modello.

whiteW = constants.whiteKeyWidthMm;       % 23.5

% Punti derivati dinamicamente dal modello (validi per qualsiasi startNote):
firstBlack    = virtualKeyboard.blackKeys(1);   % primo nero
firstWhite    = virtualKeyboard.whiteKeys(1);   % primo bianco
yInBlackBand  = constants.blackKeyLengthMm / 2; % dentro la fascia alta
yOutBlackBand = constants.blackKeyLengthMm + 20;% sotto la fascia alta

% Punto centrato sul primo bianco MA in fascia alta: se il pattern dice
% "no nero a destra del primo bianco" (es. E e B), allora il centro del
% bianco in fascia alta è SEMPRE bianco. Verifichiamo questo caso.
testPoints = [
    %  x (mm)                     y (mm)         expected idx
    firstBlack.centerMm(1),       yInBlackBand,  double(firstBlack.index);  % centro primo nero, fascia alta
    firstBlack.centerMm(1),       yOutBlackBand, NaN;                        % stessa x, fascia bassa → bianco
    firstWhite.centerMm(1),       yInBlackBand,  1;                          % centro primo bianco, fascia alta (gap)
    firstWhite.centerMm(1),       yOutBlackBand, 1;                          % centro primo bianco, fascia bassa
    -5,                           50,            0;                          % fuori a sinistra
    1e6,                          50,            0;                          % fuori a destra
    firstWhite.centerMm(1),       -1,            0;                          % y negativo → fuori
];

fprintf('\n--- Test map_point_to_key ---\n');
pts = testPoints(:, 1:2);
expected = testPoints(:, 3);
actual = map_point_to_key(pts, virtualKeyboard);

for i = 1:size(pts, 1)
    pt = pts(i, :);
    got = double(actual(i));
    exp = expected(i);
    if isnan(exp)
        verdict = '(any white, non-zero)';
        ok = got > 0 && got <= numWhite;
    else
        verdict = sprintf('expected %d', exp);
        ok = got == exp;
    end
    status = 'PASS'; if ~ok, status = 'FAIL'; end
    fprintf('  %s  (%.2f, %.2f) -> %d  [%s]\n', status, pt(1), pt(2), got, verdict);
end

%% 5. Spot-check: prima e ultima nota nera
firstBlack = virtualKeyboard.blackKeys(1);
lastBlack  = virtualKeyboard.blackKeys(end);
fprintf('\nPrimo nero: index=%d, centro=(%.1f, %.1f) mm\n', ...
    firstBlack.index, firstBlack.centerMm(1), firstBlack.centerMm(2));
fprintf('Ultimo nero: index=%d, centro=(%.1f, %.1f) mm\n', ...
    lastBlack.index, lastBlack.centerMm(1), lastBlack.centerMm(2));
fprintf('(Pattern allineato a startNote=%s)\n', virtualKeyboard.startNote);
