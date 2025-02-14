%% Info
% This code demonstrates the exemplary usage of "MSHoloSim" engine for
% simulating a set of lensless digital in-line holographic microscopy 
% (DIHM) holograms and the usage of "DarkTrack" algorithm for
% reconstructing the objects locations from the set of DIHM holograms.
% 
% List of contents
% 1. Simulating hologram with MSHoloSim and reconstructing with AS method
% 2. Simulating a set of holograms by MSHoloSim and using DarkTrack to 
%    recover objects 4D positions
% 3. Using DarkTrack to recover simulated data (spiral microbead) object 4D 
%    positions
% 4. Using DarkTrack to recover real data objects (human sperm) 4D
%    positions
%
% Exemplary datasets, that are used in 2., 3. and 4., may be downloaded at:
% https://drive.google.com/drive/folders/1UNtZ3IeEX5ms_Vx85b0S685D-uipLe_l?usp=sharing
% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Created by:
%   Mikołaj Rogalski,
%   mikolaj.rogalski.dokt@pw.edu.pl
%   Institute of Micromechanics and Photonics,
%   Warsaw University of Technology, 02-525 Warsaw, Poland
%
% Last modified: 09.06.2022
% 
% See the https://github.com/MRogalski96/DarkTrack for more info
% 
% Cite as:
% [1] Mikołaj Rogalski, Jose Angel Picazo-Bueno, Julianna Winnik, Piotr 
% Zdańkowski, Vicente Micó, Maciej Trusiak. "DarkTrack: a path across the 
% dark-field for holographic 4D particle tracking under Gabor regime." 
% 2021. Submitted
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 1. Simulating hologram with MSHoloSim and reconstructing with AS method
clear; close all; clc;

% System parameters
opts = get_system_parameters();

% Generate microbead positions and diameters
[X, Y, Z, D] = generate_microbead_positions(opts);

% Simulate hologram
[holo, u0] = MSHoloSim(X, Y, Z, D, opts);

% Display hologram simulation results
dx = opts.pixSize / opts.mag;
display_simulation_results(holo, u0, opts.imSize, dx);

% Perform reconstruction with AS method
reconstruction_results = reconstruct_holograms(holo, u0, Z, opts, dx);

% Display reconstruction results
display_reconstruction_results(reconstruction_results, Z, opts.imSize, dx);

%% 2. Simulating a set of holograms by MSHoloSim and using DarkTrack to 
% recover objects 4D positions
% Initialization and loading
clear; close all; clc;

% Load exemplary parameters
[X, Y, Z, D] = loadExemplaryParameters('./Data/ExemplaryXYZDparameters_forSimulations.mat');

%TEMP: Reduction size of data to speed up process
inds = 1:4;
X = X(:,inds); Y = Y(:,inds); Z = Z(:,inds);

% System parameters
opts = initializeSystemParameters();

% Simulating holograms
[holo, xx, yy] = simulateHolograms(X, Y, Z, D, opts);

% Display generated holograms
showGeneratedHolograms(holo, xx, yy);

% DarkTrack algorithm setup
[opts, adv] = setupDarkTrackAlgorithm(Z, opts);

% Execute DarkTrack algorithm
[outX, outY, outZ, EDOF, CR] = executeDarkTrack(holo, opts, adv);
outZ = correctOutZ(outZ);

% Display EDOF and CR results
showReconstructionResults(EDOF, CR, xx, yy);

% Display ground truth vs reconstructed positions
showGroundTruthComparison(X, Y, Z, D, outX, outY, outZ, opts, holo);

%% 3. Using DarkTrack to recover simulated data (spiral microbead) object 4D positions
clear; clc; close all;

% Load data and setup options
[X, Y, Z , D, holo, opts, adv] = loadDataAndSetup('./Data/Data from article/SimulatedData/Data_Video1.mat');

% Run DarkTrack algorithm
[outX, outY, outZ, EDOF, CR] = runDarkTrack(holo, opts, adv);

% Adjust outZ
outZ = adjustFocus(outZ);

% Display results
displayEDOFandCR(holo, opts, EDOF, CR);
displayPositions(X, Y, Z, D, holo, opts, outX, outY, outZ);
%% 4. Using DarkTrack to recover real data objects (human sperm) 4D positions
clear; clc; close all;

% Load holograms
holo = load_holograms('./Data/Data from article/RealData/HumanSpermHolo.avi');

% Load parameters
opts = load_parameters('./Data/Data from article/RealData/HumanSpermParameters.mat');

% Set advanced options
adv.NoF = 50; % Reconstruct only first 50 frames
adv.showTmpRes = 2; % Show intermediate EDOF results

% Run DarkTrack
[outX, outY, outZ, EDOF, CR] = DarkTrack(holo, opts, adv);

% Display results
display_edof_vs_cr(EDOF, CR, opts);
display_paths(outX, outY, outZ, holo, opts);



%% Functions
function uout = propagate_AS_2d(uin,z,n0,lambda,dx)
% Angular spectrum propagation method

[Ny,Nx] = size(uin);
k = 2*pi/lambda;

dfx = 1/Nx/dx; fx = -Nx/2*dfx : dfx : (Nx/2-1)*dfx;
dfy = 1/Ny/dx; fy = -Ny/2*dfy : dfy : (Ny/2-1)*dfy;

if  z<0
    kernel = exp(-1i*k*z*sqrt(n0^2 - lambda^2*(ones(Ny,1)*(fx.^2)+(fy'.^2)*ones(1,Nx))));
    ftu = kernel.*fftshift(fft2(fftshift(conj(uin))));
    uout = conj(fftshift(ifft2(ifftshift(ftu))));
else
    kernel = exp(1i*k*z*sqrt(n0^2 - lambda^2*(ones(Ny,1)*(fx.^2)+(fy'.^2)*ones(1,Nx))));
    ftu = kernel.*fftshift(fft2(fftshift(uin)));
    uout = fftshift((ifft2(ifftshift(ftu))));
end
end


function opts = get_system_parameters()
    opts.n = [1.002, 1];
    opts.A = 50; % (%)
    opts.mag = 13;
    opts.pixSize = 5.5; % (um)
    opts.dist = 0.63; % (mm)
    opts.lambda = 0.66; %(um)
    opts.SNR = 20;
    opts.imSize = 500; % (pix)
    opts.b_sig = 0.4;
    opts.ZF = 10; % Increase if out of memory
end

function [X, Y, Z, D] = generate_microbead_positions(opts)
    dx = opts.pixSize / opts.mag;
    X = [100; 100; 250; 400; 400] * dx; % (um)
    Y = [100; 400; 250; 100; 400] * dx; % (um)
    Z = [50; -50; 0; -50; 50]; % (um)
    D = [10; 8; 6; 12; 7]; % Diameters (um)
end

function display_simulation_results(holo, u0, imSize, dx)
    S = imSize;
    xx = (1:S) * dx; 
    yy = (1:S) * dx;
    
    figure;
    subplot(1, 3, 1); imagesc(xx, yy, holo); axis image;
    title('Simulated hologram'); xlabel('\mum'); ylabel('\mum');
    
    subplot(1, 3, 2); imagesc(xx, yy, abs(u0(S+1:2*S, S+1:2*S))); axis image;
    title('Optical field amplitude'); xlabel('\mum'); ylabel('\mum');
    
    subplot(1, 3, 3); imagesc(xx, yy, angle(u0(S+1:2*S, S+1:2*S))); axis image;
    title('Optical field phase'); xlabel('\mum'); ylabel('\mum');
    colormap gray;
end

function results = reconstruct_holograms(holo, u0, Z, opts, dx)
    results = struct('amplitude', [], 'phase', []);
    
    for i = 1:length(Z)
        z_pos = -opts.dist * 1000 - Z(i);
        results(i).amplitude = abs(propagate_AS_2d(holo, z_pos, opts.n(2), opts.lambda, dx));
        results(i).phase = angle(propagate_AS_2d(holo, z_pos, opts.n(2), opts.lambda, dx));
        
        % Include optical field propagation for comparison
        results(i).optical_field_amplitude = abs(propagate_AS_2d(u0, z_pos, opts.n(2), opts.lambda, dx));
        results(i).optical_field_phase = angle(propagate_AS_2d(u0, z_pos, opts.n(2), opts.lambda, dx));
    end
end

function display_reconstruction_results(results, Z, imSize, dx)
    S = imSize;
    xx = (1:S) * dx; 
    yy = (1:S) * dx;
    
    figure;
    for i = 1:length(Z)
        subplot(2, length(Z), i); imagesc(xx, yy, results(i).amplitude); axis image;
        title(['Amplitude at Z = ', num2str(Z(i)), ' \mum']); xlabel('\mum'); ylabel('\mum');
        
        subplot(2, length(Z), i + length(Z)); imagesc(xx, yy, results(i).phase); axis image;
        title(['Phase at Z = ', num2str(Z(i)), ' \mum']); xlabel('\mum'); ylabel('\mum');
    end
    colormap gray;
end

function [X, Y, Z, D] = loadExemplaryParameters(path_data)
    load(path_data);
end

function opts = initializeSystemParameters()
    opts.n = [1.002, 1];
    opts.A = 50; % (%)
    opts.mag = 13;
    opts.pixSize = 5.5; % (um)
    opts.dist = 0.63; % (mm)
    opts.lambda = 0.66; % (um)
    opts.SNR = 20;
    opts.imSize = 500; % (pix)
    opts.b_sig = 0.4;
    opts.ZF = 10; % in case of out of memory error increase the ZF parameter
end

function [holo, xx, yy] = simulateHolograms(X, Y, Z, D, opts)
    holo = MSHoloSim(X, Y, Z, D, opts);
    dx = opts.pixSize / opts.mag;
    xx = (1:size(holo, 2)) * dx;
    yy = (1:size(holo, 1)) * dx;
end

function showGeneratedHolograms(holo, xx, yy)
    figure;
    NoH = size(holo, 3);
    for tt = 1:NoH
        imagesc(xx, yy, holo(:, :, tt));
        title(['Simulated hologram ', num2str(tt), '/', num2str(NoH)]);
        xlabel('\mum'); ylabel('\mum'); colormap gray; axis image;
        pause(0.1);
    end
end

function [opts, adv] = setupDarkTrackAlgorithm(Z, opts)
    opts.propRange = [min(Z(:)) - 30, max(Z(:)) + 30]; % (um)
    opts.propStep = 1; % (um)
    adv.showTmpRes = 2; % additionally show the EDOF results during reconstruction
end

function [outX, outY, outZ, EDOF, CR] = executeDarkTrack(holo, opts, adv)
    [outX, outY, outZ, EDOF, CR] = DarkTrack(holo, opts, adv);
end

function outZ = correctOutZ(outZ)
    outZ = outZ + 2; % Compensate for focus position offset
end

function showReconstructionResults(EDOF, CR, xx, yy)
    miEDOF = min(EDOF(:)); maEDOF = max(EDOF(:));
    miCR = min(CR(:)); maCR = max(CR(:));
    figure('units', 'normalized', 'outerposition', [0 0 1 1]);
    NoH = size(EDOF, 3);
    for tt = 1:NoH
        subplot(1, 2, 1);
        imagesc(xx, yy, EDOF(:, :, tt), [miEDOF, maEDOF]); axis image;
        xlabel('\mum'); ylabel('\mum'); colormap gray;
        title(['EDOF reconstruction ', num2str(tt), '/', num2str(NoH)]);
        set(gca, 'fontsize', 20);

        subplot(1, 2, 2);
        imagesc(xx, yy, CR(:, :, tt), [miCR, maCR]); axis image;
        xlabel('\mum'); ylabel('\mum'); colormap gray;
        title(['CR reconstruction at the middle of propRange ', num2str(tt), '/', num2str(NoH)]);
        set(gca, 'fontsize', 20);

        pause(0.1);
    end
end

function showGroundTruthComparison(X, Y, Z, D, outX, outY, outZ, opts, holo)
    figure; plot3(X(:), Y(:), Z(:), '.k'); hold on;
    C = [X(1, end), Y(1, end), Z(1, end)]; % Center of circle
    R = D(1) / 2; % Radius of circle
    teta = 0:0.01:2*pi;
    x = C(1) + R * cos(teta);
    z = C(3) + R * sin(teta);
    y2 = C(2) + R * sin(teta);
    y = C(2) + zeros(size(x));
    z2 = C(3) + zeros(size(x));
    plot3([x, x], [y, y2], [z, z2], '-r', 'Linewidth', 2);
    plot3(outX', outY', outZ', '.-'); grid on; hold off;
    axis equal;
    dx = opts.pixSize / opts.mag;
    xlim([dx, dx * size(holo, 2)]);
    ylim([dx, dx * size(holo, 1)]);
    zlim([opts.propRange(1), opts.propRange(2)]);
    xlabel('x [\mum]');
    ylabel('y [\mum]');
    zlabel('z [\mum]');
    title('Microbeads paths of movement');

    nms = cell(1, 12);
    nms{1} = 'ground truth positions';
    nms{2} = 'microbead size';
    for ss = 3:12
        nms{ss} = ['microbead ', num2str(ss - 2)];
    end
    legend(nms);
    set(gca, 'YDir', 'reverse');
end


function [X, Y, Z, D, holo, opts, adv] = loadDataAndSetup(path_data)
    load(path_data);
    clear u0;
    
    adv.showTmpRes = 2; % Show EDOF results during reconstruction
end

function [outX, outY, outZ, EDOF, CR] = runDarkTrack(holo, opts, adv)
    [outX, outY, outZ, EDOF, CR] = DarkTrack(holo, opts, adv);
end

function outZ = adjustFocus(outZ)
    outZ = outZ + 1; % Adjust focus position slightly above the microbead center
end

function displayEDOFandCR(holo, opts, EDOF, CR)
    NoH = size(holo, 3);
    dx = opts.pixSize / opts.mag;
    xx = (1:size(holo, 2)) * dx; 
    yy = (1:size(holo, 1)) * dx;
    
    miEDOF = min(EDOF(:)); 
    maEDOF = max(EDOF(:));
    miCR = min(CR(:)); 
    maCR = max(CR(:));

    figure('units', 'normalized', 'outerposition', [0 0 1 1]);
    for tt = 1:NoH
        subplot(1, 2, 1);
        imagesc(xx, yy, EDOF(:, :, tt), [miEDOF, maEDOF]);
        axis image; xlabel('\mum'); ylabel('\mum'); colormap gray;
        title(['EDOF reconstruction ', num2str(tt), '/', num2str(NoH)]);

        subplot(1, 2, 2);
        imagesc(xx, yy, CR(:, :, tt), [miCR, maCR]);
        axis image; xlabel('\mum'); ylabel('\mum'); colormap gray;
        title(['CR reconstruction at middle of propRange ', num2str(tt), '/', num2str(NoH)]);

        pause(0.1);
    end
end

function displayPositions(X, Y, Z, D, holo, opts, outX, outY, outZ)
    dx = opts.pixSize / opts.mag;
    
    figure;
    plot3(X(:), Y(:), Z(:), '.k');
    hold on;

    % Circle parameters
    C = [X(1, end), Y(1, end), Z(1, end)];
    R = D(1) / 2;
    theta = 0:0.01:2*pi;
    x = C(1) + R * cos(theta);
    z = C(3) + R * sin(theta);
    y2 = C(2) + R * sin(theta);
    y = C(2) + zeros(size(x));
    z2 = C(3) + zeros(size(x));
    
    % Plot circle and paths
    plot3([x, x], [y, y2], [z, z2], '-r', 'LineWidth', 2);
    plot3(outX', outY', outZ', '.-');
    grid on;
    hold off;
    axis equal;

    % Set limits and labels
    xlim([dx, dx * size(holo, 2)]);
    ylim([dx, dx * size(holo, 1)]);
    zlim([opts.propRange(1), opts.propRange(2)]);
    xlabel('x [\mum]');
    ylabel('y [\mum]');
    zlabel('z [\mum]');
    title('Microbeads paths of movement');

    % Add legend
    nms = {'ground truth positions', 'microbead size'};
    for ss = 3:size(outX, 1) + 2
        nms{ss} = ['microbead ', num2str(ss - 2)];
    end
    legend(nms);
    set(gca, 'YDir', 'reverse');
end

function holo = load_holograms(video_path)
    mov = VideoReader(video_path);
    t = 0;
    while hasFrame(mov)
        t = t + 1;
        frame = readFrame(mov);
        holo(:, :, t) = frame(:, :, 3);
    end
end

function opts = load_parameters(params_path)
    load(params_path, 'opts');
end

function display_edof_vs_cr(EDOF, CR, opts)
    dx = opts.pixSize / opts.mag;
    xx = (1:size(EDOF, 2)) * dx; 
    yy = (1:size(EDOF, 1)) * dx;

    miEDOF = min(EDOF(:)); 
    maEDOF = max(EDOF(:));
    miCR = min(CR(:)); 
    maCR = max(CR(:));

    figure('units', 'normalized', 'outerposition', [0 0 1 1]);
    NoH = size(EDOF, 3);

    for tt = 1:NoH
        subplot(1, 2, 1); 
        imagesc(xx, yy, EDOF(:, :, tt), [miEDOF, maEDOF]); 
        axis image; xlabel('\mum'); ylabel('\mum'); colormap gray;
        title(['EDOF reconstruction ', num2str(tt), '/', num2str(NoH)]);

        subplot(1, 2, 2); 
        imagesc(xx, yy, CR(:, :, tt), [miCR, maCR]); 
        axis image; xlabel('\mum'); ylabel('\mum'); colormap gray;
        title(['CR reconstruction ', num2str(tt), '/', num2str(NoH)]);

        pause(0.1);
    end
end

function display_paths(outX, outY, outZ, holo, opts)
    dx = opts.pixSize / opts.mag;
    m = min(size(outX, 1), 5);

    for tt = 0:m
        figure;
        plot3(outX', outY', outZ', '.-'); grid on;
        axis equal;
        xlim([dx, dx * size(holo, 2)]);
        ylim([dx, dx * size(holo, 1)]);
        zlim([opts.propRange(1), opts.propRange(2)]);
        xlabel('x [\mum]'); ylabel('y [\mum]'); zlabel('z [\mum]');
        title('Human sperm paths of movement');
        set(gca, 'YDir', 'reverse');

        if tt > 0
            xlim([min(outX(tt, :)), max(outX(tt, :))]);
            ylim([min(outY(tt, :)), max(outY(tt, :))]);
            zlim([min(outZ(tt, :)), max(outZ(tt, :))]);
            title('Single spermatozoid movement path');
        end
    end
end